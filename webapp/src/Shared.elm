module Shared exposing
    ( Flags, decoder
    , Model, Msg
    , init, update, subscriptions
    )

{-|

@docs Flags, decoder
@docs Model, Msg
@docs init, update, subscriptions

-}

import Effect exposing (Effect)
import Json.Decode
import Json.Decode as D
import Route exposing (Route)
import Shared.Model exposing (Entry, ListMeta)
import Shared.Msg



-- FLAGS


type alias Flags =
    { lists : List ListMeta
    , entries : List Entry
    }


decoder : Json.Decode.Decoder Flags
decoder =
    D.map2 Flags
        (D.field "lists" (D.list listMetaDecoder))
        (D.field "entries" (D.list entryDecoder))


listMetaDecoder : D.Decoder ListMeta
listMetaDecoder =
    D.map3 ListMeta
        (D.field "id" D.string)
        (D.field "name" D.string)
        (D.field "repo" D.string)


entryDecoder : D.Decoder Entry
entryDecoder =
    D.map7 Entry
        (D.field "list" D.string)
        (D.field "category" D.string)
        (D.field "subcategory" (D.nullable D.string))
        (D.field "name" D.string)
        (D.field "url" D.string)
        (D.field "description" D.string)
        (D.field "tags" (D.list D.string))



-- INIT


type alias Model =
    Shared.Model.Model


init : Result Json.Decode.Error Flags -> Route () -> ( Model, Effect Msg )
init flagsResult _ =
    case flagsResult of
        Ok flags ->
            ( { lists = flags.lists
              , entries = flags.entries
              , loadError = Nothing
              }
            , Effect.none
            )

        Err err ->
            ( { lists = []
              , entries = []
              , loadError = Just (D.errorToString err)
              }
            , Effect.none
            )



-- UPDATE


type alias Msg =
    Shared.Msg.Msg


update : Route () -> Msg -> Model -> ( Model, Effect Msg )
update _ msg model =
    case msg of
        Shared.Msg.NoOp ->
            ( model
            , Effect.none
            )



-- SUBSCRIPTIONS


subscriptions : Route () -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none
