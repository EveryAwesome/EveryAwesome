module Pages.Home_ exposing (Model, Msg, page)

import Dict exposing (Dict)
import Effect exposing (Effect)
import Html exposing (Html, a, button, div, h1, h2, h3, header, input, li, main_, nav, p, section, span, text, ul)
import Html.Attributes exposing (attribute, class, classList, href, placeholder, target, type_, value)
import Html.Events exposing (onClick, onInput)
import Page exposing (Page)
import Process
import Route exposing (Route)
import Set exposing (Set)
import Shared
import Shared.Model exposing (Entry, ListMeta)
import Task
import View exposing (View)


page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = init route
        , update = update route
        , subscriptions = \_ -> Sub.none
        , view = view shared
        }
        |> Page.withOnQueryParameterChanged
            { key = listsQueryKey
            , onChange = ListsQueryChanged
            }


listsQueryKey : String
listsQueryKey =
    "lists"



-- CONSTANTS


maxVisibleEntries : Int
maxVisibleEntries =
    200


debounceMillis : Float
debounceMillis =
    150



-- MODEL


type alias Model =
    { rawQuery : String
    , query : String
    , debounceToken : Int
    , selectedLists : Set String
    , selectedCategories : Set String
    , selectedTags : Set String
    , visibleCount : Int
    }


init : Route () -> () -> ( Model, Effect Msg )
init route () =
    ( { rawQuery = ""
      , query = ""
      , debounceToken = 0
      , selectedLists = parseListsParam (Dict.get listsQueryKey route.query)
      , selectedCategories = Set.empty
      , selectedTags = Set.empty
      , visibleCount = maxVisibleEntries
      }
    , Effect.none
    )


parseListsParam : Maybe String -> Set String
parseListsParam param =
    case param of
        Nothing ->
            Set.empty

        Just s ->
            s
                |> String.split ","
                |> List.filter (not << String.isEmpty)
                |> Set.fromList


encodeListsParam : Set String -> Dict String String -> Dict String String
encodeListsParam selected query =
    if Set.isEmpty selected then
        Dict.remove listsQueryKey query

    else
        Dict.insert listsQueryKey (Set.toList selected |> String.join ",") query



-- UPDATE


type Msg
    = QueryChanged String
    | ApplyQuery Int
    | ToggleList String
    | ToggleCategory String
    | ToggleTag String
    | ClearFilters
    | ShowMore
    | ListsQueryChanged { from : Maybe String, to : Maybe String }


update : Route () -> Msg -> Model -> ( Model, Effect Msg )
update route msg model =
    case msg of
        QueryChanged q ->
            let
                token =
                    model.debounceToken + 1
            in
            ( { model | rawQuery = q, debounceToken = token }
            , debounce debounceMillis (ApplyQuery token)
            )

        ApplyQuery token ->
            if token == model.debounceToken then
                ( { model | query = model.rawQuery, visibleCount = maxVisibleEntries }
                , Effect.none
                )

            else
                ( model, Effect.none )

        ToggleList id ->
            let
                newSelected =
                    toggle id model.selectedLists
            in
            ( { model
                | selectedLists = newSelected
                , selectedCategories = Set.empty
                , visibleCount = maxVisibleEntries
              }
            , Effect.replaceRoute
                { path = route.path
                , query = encodeListsParam newSelected route.query
                , hash = route.hash
                }
            )

        ToggleCategory cat ->
            ( { model | selectedCategories = toggle cat model.selectedCategories, visibleCount = maxVisibleEntries }
            , Effect.none
            )

        ToggleTag tag ->
            ( { model | selectedTags = toggle tag model.selectedTags, visibleCount = maxVisibleEntries }
            , Effect.none
            )

        ClearFilters ->
            ( { model
                | rawQuery = ""
                , query = ""
                , debounceToken = model.debounceToken + 1
                , selectedLists = Set.empty
                , selectedCategories = Set.empty
                , selectedTags = Set.empty
                , visibleCount = maxVisibleEntries
              }
            , Effect.replaceRoute
                { path = route.path
                , query = Dict.remove listsQueryKey route.query
                , hash = route.hash
                }
            )

        ShowMore ->
            ( { model | visibleCount = model.visibleCount + maxVisibleEntries }
            , Effect.none
            )

        ListsQueryChanged { to } ->
            ( { model | selectedLists = parseListsParam to, visibleCount = maxVisibleEntries }
            , Effect.none
            )


debounce : Float -> msg -> Effect msg
debounce ms msg =
    Process.sleep ms
        |> Task.perform (\_ -> msg)
        |> Effect.sendCmd


toggle : comparable -> Set comparable -> Set comparable
toggle item set =
    if Set.member item set then
        Set.remove item set

    else
        Set.insert item set



-- FILTERING


{-| Greedy subsequence-style fuzzy scorer.

Returns `Nothing` if the query characters don't appear in order in the
haystack. Returns `Just n` otherwise, where higher = better match.

Scoring (per matched query char):

  - Base: +1
  - Consecutive (this match's index = previous match's index + 1): +5
  - Word-boundary (matched char is preceded by a non-alphanumeric, or is
    the first char): +3

This is greedy — it takes the first occurrence of each query char in
order — which is fast and good enough for a 1k-entry dataset. Empty
query returns `Just 0` so the filter passes everything.

-}
fuzzyScore : String -> String -> Maybe Int
fuzzyScore query haystack =
    if String.isEmpty query then
        Just 0

    else
        scoreLoop
            (String.toList (String.toLower query))
            (String.toList (String.toLower haystack))
            0
            -2
            ' '
            0


scoreLoop : List Char -> List Char -> Int -> Int -> Char -> Int -> Maybe Int
scoreLoop query hay idx lastMatchIdx prevChar acc =
    case query of
        [] ->
            Just acc

        q :: qs ->
            case hay of
                [] ->
                    Nothing

                h :: hs ->
                    if h == q then
                        let
                            consecutiveBonus =
                                if idx == lastMatchIdx + 1 then
                                    5

                                else
                                    0

                            boundaryBonus =
                                if idx == 0 || not (Char.isAlphaNum prevChar) then
                                    3

                                else
                                    0
                        in
                        scoreLoop qs hs (idx + 1) idx h (acc + 1 + consecutiveBonus + boundaryBonus)

                    else
                        scoreLoop (q :: qs) hs (idx + 1) lastMatchIdx h acc


{-| Score an entry: matches against name (weighted 2x) and description, takes the best.
-}
queryScore : String -> Entry -> Maybe Int
queryScore query entry =
    if String.isEmpty query then
        Just 0

    else
        let
            nameScore =
                fuzzyScore query entry.name |> Maybe.map (\s -> s * 2)

            descScore =
                fuzzyScore query entry.description
        in
        case ( nameScore, descScore ) of
            ( Just n, Just d ) ->
                Just (max n d)

            ( Just n, Nothing ) ->
                Just n

            ( Nothing, Just d ) ->
                Just d

            ( Nothing, Nothing ) ->
                Nothing


passesSet : Set String -> String -> Bool
passesSet set value =
    Set.isEmpty set || Set.member value set


passesTagSet : Set String -> List String -> Bool
passesTagSet set tags =
    Set.isEmpty set || List.any (\t -> Set.member t set) tags


{-| Apply categorical filters then score by query. Returns entries paired with
their score so the caller can sort by relevance.
-}
applyFilters : Model -> List Entry -> List Entry
applyFilters model entries =
    let
        scored =
            entries
                |> List.filter (\e -> passesSet model.selectedLists e.list)
                |> List.filter (\e -> passesSet model.selectedCategories e.category)
                |> List.filter (\e -> passesTagSet model.selectedTags e.tags)
                |> List.filterMap
                    (\e ->
                        queryScore model.query e
                            |> Maybe.map (\score -> ( score, e ))
                    )
    in
    if String.isEmpty model.query then
        List.map Tuple.second scored

    else
        scored
            |> List.sortBy (\( s, _ ) -> -s)
            |> List.map Tuple.second


{-| Used by the sidebar to count how many entries each filter option would
yield. Doesn't need scoring, just match/no-match.
-}
matchesQuery : String -> Entry -> Bool
matchesQuery query entry =
    queryScore query entry /= Nothing



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "EveryAwesome"
    , body = [ viewBody shared model ]
    }


viewBody : Shared.Model -> Model -> Html Msg
viewBody shared model =
    case shared.loadError of
        Just err ->
            viewLoadError err

        Nothing ->
            let
                filtered =
                    applyFilters model shared.entries

                visible =
                    List.take model.visibleCount filtered
            in
            div [ class "min-h-screen bg-slate-50 text-slate-900" ]
                [ viewHeader model (List.length filtered) (List.length shared.entries)
                , div [ class "mx-auto max-w-7xl px-4 py-6 lg:flex lg:gap-8" ]
                    [ viewSidebar shared model
                    , main_ [ class "flex-1 mt-6 lg:mt-0" ]
                        [ viewEntries visible
                        , viewShowMore (List.length filtered) model.visibleCount
                        ]
                    ]
                ]


viewLoadError : String -> Html msg
viewLoadError err =
    div [ class "min-h-screen flex items-center justify-center bg-red-50 p-8" ]
        [ div [ class "max-w-2xl bg-white border border-red-300 rounded p-6 shadow" ]
            [ h1 [ class "text-xl font-semibold text-red-800 mb-2" ] [ text "Failed to load data" ]
            , p [ class "text-sm text-red-700 mb-4" ] [ text "The /entries.json file could not be parsed. Run `make parse` and reload." ]
            , Html.pre [ class "text-xs text-slate-700 bg-slate-100 p-3 rounded overflow-auto" ] [ text err ]
            ]
        ]


viewHeader : Model -> Int -> Int -> Html Msg
viewHeader model filteredCount totalCount =
    header [ class "sticky top-0 z-10 bg-white border-b border-slate-200 shadow-sm" ]
        [ div [ class "mx-auto max-w-7xl px-4 py-3 flex flex-col sm:flex-row sm:items-center gap-3" ]
            [ h1 [ class "text-xl font-semibold tracking-tight" ]
                [ text "Every"
                , span [ class "text-indigo-600" ] [ text "Awesome" ]
                ]
            , div [ class "flex-1 flex items-center gap-2" ]
                [ input
                    [ type_ "search"
                    , placeholder "Search names and descriptions…"
                    , value model.rawQuery
                    , onInput QueryChanged
                    , attribute "autofocus" ""
                    , class "flex-1 px-3 py-2 border border-slate-300 rounded focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    ]
                    []
                ]
            , div [ class "text-sm text-slate-500 whitespace-nowrap" ]
                [ text (String.fromInt filteredCount ++ " of " ++ String.fromInt totalCount) ]
            , if hasActiveFilters model then
                button
                    [ onClick ClearFilters
                    , class "text-sm px-3 py-1.5 rounded border border-slate-300 hover:bg-slate-100"
                    ]
                    [ text "Clear filters" ]

              else
                text ""
            ]
        ]


hasActiveFilters : Model -> Bool
hasActiveFilters model =
    not (String.isEmpty model.rawQuery)
        || not (Set.isEmpty model.selectedLists)
        || not (Set.isEmpty model.selectedCategories)
        || not (Set.isEmpty model.selectedTags)



-- SIDEBAR


viewSidebar : Shared.Model -> Model -> Html Msg
viewSidebar shared model =
    let
        -- Counts must reflect what would happen if user toggles each option:
        -- compute on entries pre-filtered by all OTHER filters.
        baseEntries =
            shared.entries
                |> List.filter (matchesQuery model.query)

        -- For list counts: filter by everything except selectedLists
        entriesForListCounts =
            baseEntries
                |> List.filter (\e -> passesSet model.selectedCategories e.category)
                |> List.filter (\e -> passesTagSet model.selectedTags e.tags)

        listCounts =
            tally .list entriesForListCounts

        -- For category counts: filter by everything except selectedCategories
        entriesForCategoryCounts =
            baseEntries
                |> List.filter (\e -> passesSet model.selectedLists e.list)
                |> List.filter (\e -> passesTagSet model.selectedTags e.tags)

        categoryCounts =
            tally .category entriesForCategoryCounts

        -- For tag counts: filter by everything except selectedTags
        entriesForTagCounts =
            baseEntries
                |> List.filter (\e -> passesSet model.selectedLists e.list)
                |> List.filter (\e -> passesSet model.selectedCategories e.category)

        tagCounts =
            tallyTags entriesForTagCounts
    in
    nav [ class "lg:w-72 lg:flex-shrink-0 lg:sticky lg:top-20 lg:self-start lg:max-h-[calc(100vh-6rem)] lg:overflow-y-auto space-y-6" ]
        [ viewListFilter shared.lists listCounts model.selectedLists
        , viewCategoryFilter categoryCounts model.selectedCategories
        , viewTagFilter tagCounts model.selectedTags
        ]


viewListFilter : List ListMeta -> Dict String Int -> Set String -> Html Msg
viewListFilter lists counts selected =
    section [ class "bg-white border border-slate-200 rounded p-3" ]
        [ h2 [ class "text-xs font-semibold text-slate-500 uppercase tracking-wide mb-2" ] [ text "Lists" ]
        , ul [ class "space-y-1" ]
            (lists |> List.map (viewListRow counts selected))
        ]


viewListRow : Dict String Int -> Set String -> ListMeta -> Html Msg
viewListRow counts selected meta =
    let
        isSelected =
            Set.member meta.id selected

        count =
            Dict.get meta.id counts |> Maybe.withDefault 0
    in
    li [ class "flex items-stretch gap-1" ]
        [ button
            [ onClick (ToggleList meta.id)
            , classList
                [ ( "flex-1 flex items-center justify-between text-left px-2 py-1 rounded text-sm transition-colors", True )
                , ( "bg-indigo-50 text-indigo-900 font-medium", isSelected )
                , ( "hover:bg-slate-100 text-slate-700", not isSelected )
                ]
            ]
            [ span [ class "truncate pr-2" ] [ text meta.name ]
            , span [ class "text-xs text-slate-500 tabular-nums" ] [ text (String.fromInt count) ]
            ]
        , a
            [ href ("https://github.com/" ++ meta.repo)
            , target "_blank"
            , attribute "rel" "noopener noreferrer"
            , attribute "title" ("Open " ++ meta.repo ++ " on GitHub")
            , class "px-2 flex items-center text-slate-400 hover:text-indigo-700 hover:bg-slate-100 rounded text-sm"
            ]
            [ text "↗" ]
        ]


viewCategoryFilter : Dict String Int -> Set String -> Html Msg
viewCategoryFilter counts selected =
    let
        sorted =
            counts
                |> Dict.toList
                |> List.sortBy (\( _, n ) -> -n)
    in
    if List.isEmpty sorted then
        text ""

    else
        section [ class "bg-white border border-slate-200 rounded p-3" ]
            [ h2 [ class "text-xs font-semibold text-slate-500 uppercase tracking-wide mb-2" ] [ text "Categories" ]
            , ul [ class "space-y-1" ]
                (sorted
                    |> List.map
                        (\( cat, n ) ->
                            viewFilterRow
                                { label = cat
                                , value = cat
                                , count = n
                                , selected = Set.member cat selected
                                , onToggle = ToggleCategory cat
                                }
                        )
                )
            ]


viewTagFilter : Dict String Int -> Set String -> Html Msg
viewTagFilter counts selected =
    let
        sorted =
            counts
                |> Dict.toList
                |> List.sortBy (\( _, n ) -> -n)
                |> List.take 30
    in
    if List.isEmpty sorted then
        text ""

    else
        section [ class "bg-white border border-slate-200 rounded p-3" ]
            [ h2 [ class "text-xs font-semibold text-slate-500 uppercase tracking-wide mb-2" ] [ text "Tags" ]
            , div [ class "flex flex-wrap gap-1" ]
                (sorted
                    |> List.map
                        (\( tag, n ) ->
                            button
                                [ onClick (ToggleTag tag)
                                , classList
                                    [ ( "px-2 py-0.5 rounded text-xs border", True )
                                    , ( "bg-indigo-600 text-white border-indigo-600", Set.member tag selected )
                                    , ( "bg-slate-100 text-slate-700 border-slate-200 hover:bg-slate-200", not (Set.member tag selected) )
                                    ]
                                ]
                                [ text tag
                                , span [ class "ml-1 opacity-70" ] [ text (String.fromInt n) ]
                                ]
                        )
                )
            ]


viewFilterRow :
    { label : String
    , value : String
    , count : Int
    , selected : Bool
    , onToggle : Msg
    }
    -> Html Msg
viewFilterRow { label, count, selected, onToggle } =
    li []
        [ button
            [ onClick onToggle
            , classList
                [ ( "w-full flex items-center justify-between text-left px-2 py-1 rounded text-sm transition-colors", True )
                , ( "bg-indigo-50 text-indigo-900 font-medium", selected )
                , ( "hover:bg-slate-100 text-slate-700", not selected )
                ]
            ]
            [ span [ class "truncate pr-2" ] [ text label ]
            , span [ class "text-xs text-slate-500 tabular-nums" ] [ text (String.fromInt count) ]
            ]
        ]



-- ENTRIES


viewEntries : List Entry -> Html Msg
viewEntries entries =
    if List.isEmpty entries then
        div [ class "text-center py-16 text-slate-500" ]
            [ p [ class "text-lg" ] [ text "No matches" ]
            , p [ class "text-sm mt-1" ] [ text "Try a different search or clear some filters." ]
            ]

    else
        ul [ class "space-y-2" ] (List.map viewEntry entries)


viewEntry : Entry -> Html Msg
viewEntry entry =
    li [ class "bg-white border border-slate-200 rounded p-3 hover:border-indigo-300 transition-colors" ]
        [ div [ class "flex items-baseline gap-2 flex-wrap" ]
            [ a
                [ href entry.url
                , target "_blank"
                , attribute "rel" "noopener noreferrer"
                , class "text-base font-semibold text-indigo-700 hover:underline"
                ]
                [ text entry.name ]
            , viewBreadcrumb entry
            ]
        , if String.isEmpty entry.description then
            text ""

          else
            p [ class "text-sm text-slate-600 mt-1" ] [ text entry.description ]
        , if List.isEmpty entry.tags then
            text ""

          else
            div [ class "mt-2 flex flex-wrap gap-1" ]
                (entry.tags |> List.map viewTagChip)
        ]


viewBreadcrumb : Entry -> Html Msg
viewBreadcrumb entry =
    let
        sep =
            span [ class "text-slate-400 px-1" ] [ text "›" ]

        crumb t =
            span [ class "text-slate-500" ] [ text t ]

        parts =
            [ Just (crumb entry.list), Just (crumb entry.category), Maybe.map crumb entry.subcategory ]
                |> List.filterMap identity
                |> List.intersperse sep
    in
    span [ class "text-xs flex items-baseline" ] parts


viewTagChip : String -> Html msg
viewTagChip tag =
    span [ class "px-1.5 py-0.5 bg-slate-100 text-slate-600 text-xs rounded" ] [ text tag ]


viewShowMore : Int -> Int -> Html Msg
viewShowMore total visible =
    if total > visible then
        div [ class "mt-4 text-center" ]
            [ button
                [ onClick ShowMore
                , class "px-4 py-2 bg-white border border-slate-300 rounded hover:bg-slate-50 text-sm font-medium"
                ]
                [ text ("Show more (" ++ String.fromInt (total - visible) ++ " remaining)") ]
            ]

    else
        text ""



-- HELPERS


tally : (a -> String) -> List a -> Dict String Int
tally getKey items =
    List.foldl
        (\item acc -> Dict.update (getKey item) (Maybe.withDefault 0 >> (+) 1 >> Just) acc)
        Dict.empty
        items


tallyTags : List Entry -> Dict String Int
tallyTags entries =
    List.foldl
        (\entry acc ->
            List.foldl
                (\tag a -> Dict.update tag (Maybe.withDefault 0 >> (+) 1 >> Just) a)
                acc
                entry.tags
        )
        Dict.empty
        entries
