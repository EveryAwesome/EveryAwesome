module Shared.Model exposing (Model, ListMeta, Entry)

{-| -}


type alias Model =
    { lists : List ListMeta
    , entries : List Entry
    , loadError : Maybe String
    }


type alias ListMeta =
    { id : String
    , name : String
    , repo : String
    }


type alias Entry =
    { list : String
    , category : String
    , subcategory : Maybe String
    , name : String
    , url : String
    , description : String
    , tags : List String
    }
