# yesod-generate-rest

A domain specific language and a code generator desined to create RESTful
JSON-only web services for managing a database with [Yesod web framework](http://www.yesodweb.com/)
and [Persistent](http://www.yesodweb.com/book/persistent).

This code generator borrowes some code from
[yesod-generate](http://github.com/maxcan/yesod-generate/). The original
yesod-generate supports also non-JSON web services. 

## Features (parentheses if not yet implemented)
 * splitting database definitions into multiple files
 * generates support code for implementing polymorphic relations and accessing common fields
 * generates boilerplate code for entity validation
 * supports following field types : Word32, Word64, Int32, Int64, Text, Bool, Double, TimeOfDay, Day, UTCTime, ZonedTime
 * generates RESTful JSON web service for managing entities 
 * hooks to user-supplied pre and post service hooks (e.g. checking if user is allowed to retrieve a particular record, or logging changes)
 * (generating default filtering and sorting code)

## License
 * The code generator is distributed under the terms of [Simplified BSD license](LICENSE)

## Quick start

### Step 1: get the source code and compile

    git clone git://github.com/tlaitinen/yesod-generate-rest.git
    cd yesod-generate-rest
    make

### Step 2: Create scaffolded Yesod site

    yesod init

### Step 3: write database and service definition file
```
-- other files can be included for increased modularity
-- import "module.def";

-- class defines a set of fields that can be inherited by an entity
class Named {
    name Text check nonempty;
}

class Versioned {
    version Maybe Int64; 
}

-- User-entity is an instance of the classes Named and Versioned
entity Person : Named, Versioned {
    language Text check validLanguage;
    timezone Text check validTimezone;

    -- service definitions start here
    get { 
        -- GET service does not require authentication
        public;

        -- pre-hooks can be used to check if a particular
        -- record can be retrieved
        pre-hook personGetAllowed;

        -- post-hooks are run at the end of the handler
        post-hook logPersonGet;

        -- ExtJS compatible filtering and sorting parameters
        -- can be generated by including the following keyword
        default-filter-sort; 

        -- additional user-supplied filtering and sorting functions can be added
        filter filterPersons;
        select-opts sortPersons;
    }
    post {}
    delete {}
    put {}
    validate {
        -- validate is like post-handler but does not 
        -- insert the entity to database
    }
}

entity Note : Named, Versioned {
    owner   Person;
    body    Text;
    created DateTime;
    get { 
    }
    post {}
    delete {}
    put {}
    validate {}
}

entity FileItem : Named {
    owner Person;
    path Text;

    -- uniqueness definitions are supported
    unique OwnerName owner name;

    -- entity-wide check functions can be added, too
    check validFileItem;
}

entity ChangeRecord {
    field    Text;
    oldValue Text;
    newValue Text;
    time     DateTime;
    version  Int64;

    -- a polymorphic relation which will be expanded to a number of fields
    -- pointing a each possible entity that is an instance of Versioned
    'entity' Maybe Versioned;
}
```

### Step 4: run code generator

    $ yesod-generate-rest main.def

At the moment, the code generator writes config/generated-models, config/generated-routes, Model/Json.hs, Model/Validation.hs, Model/Classes.hs, and Handler/Generated.hs have the following contents.


#### config/generated-models
```
ChangeRecord json
    entityNote NoteId Maybe 
    entityPerson PersonId Maybe 
    version Int64 
    time UTCTime 
    newValue Text 
    oldValue Text 
    field Text 

FileItem json
    path Text 
    owner PersonId 
    name Text 
    UniqueOwnerName owner name

Note json
    created UTCTime 
    body Text 
    owner PersonId 
    version Int64 Maybe 
    name Text 

Person json
    timezone Text 
    language Text 
    version Int64 Maybe 
    name Text 
```

#### Model/generated-routes
```
/note NoteManyR GET POST
/note/#NoteId NoteR GET PUT DELETE
/validate/note NoteValidateR POST
/person PersonManyR GET POST
/person/#PersonId PersonR GET PUT DELETE
/validate/person PersonValidateR POST
```

TODO: Hmm.. how to add another routes file to Yesod site...

#### Model/Validation.hs
```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ExistentialQuantification #-}
module Model.Validation (Validatable(..)) where
import Data.Text
import qualified Model.ValidationFunctions as V
import Import
checkResult :: forall (m :: * -> *). (Monad m) => Text -> m Bool -> m Text
checkResult msg f = do
   result <- f
   return $ if result then "" else msg

class Validatable a where
    validate :: forall m. (PersistQuery m, PersistEntityBackend a ~ PersistMonadBackend m) => a -> m [Text]
instance Validatable ChangeRecord where 
    validate e = sequence [
        ]

instance Validatable FileItem where 
    validate e = sequence [
        checkResult "FileItem.name nonempty" (V.nonempty $ fileItemName e),
        checkResult "FileItem validFileItem" (V.validFileItem e)
        ]

instance Validatable Note where 
    validate e = sequence [
        checkResult "Note.name nonempty" (V.nonempty $ noteName e)
        ]

instance Validatable Person where 
    validate e = sequence [
        checkResult "Person.timezone validTimezone" (V.validTimezone $ personTimezone e),
        checkResult "Person.language validLanguage" (V.validLanguage $ personLanguage e),
        checkResult "Person.name nonempty" (V.nonempty $ personName e)
        ]

``

#### Model/Classes.hs
```haskell
module Model.Classes where
import Import
import Data.Int
import Data.Word
import Data.Time
class Versioned a where
    versionedVersion :: a -> Maybe Int64

instance Versioned Note where 
    versionedVersion = noteVersion

instance Versioned Person where 
    versionedVersion = personVersion

class Named a where
    namedName :: a -> Text

instance Named FileItem where 
    namedName = fileItemName

instance Named Note where 
    namedName = noteName

instance Named Person where 
    namedName = personName
```

#### Model/Json.hs

```haskell
{-# LANGUAGE FlexibleInstances #-}
module Model.Json where
import Import
import Data.Aeson
import qualified Data.HashMap.Lazy as HML
instance ToJSON (Entity ChangeRecord) where
    toJSON (Entity k v) = case toJSON v of
        Object o -> Object $ HML.insert "id" (toJSON k) o
        _ -> error "unexpected JS encode error"
instance ToJSON (Entity FileItem) where
    toJSON (Entity k v) = case toJSON v of
        Object o -> Object $ HML.insert "id" (toJSON k) o
        _ -> error "unexpected JS encode error"
instance ToJSON (Entity Note) where
    toJSON (Entity k v) = case toJSON v of
        Object o -> Object $ HML.insert "id" (toJSON k) o
        _ -> error "unexpected JS encode error"
instance ToJSON (Entity Person) where
    toJSON (Entity k v) = case toJSON v of
        Object o -> Object $ HML.insert "id" (toJSON k) o
        _ -> error "unexpected JS encode error"
```

#### Handler/Generated.hs
```haskell
module Handler.Generated where 
import Import
import Yesod.Auth
import Model.Validation
import Model.Json ()
import Data.Aeson (json)
import Data.Maybe
import Data.Aeson.Types (emptyObject)
import Handler.Hooks

postNoteValidateR :: Handler RepJson
postNoteValidateR = do
    entity <- parseJsonBody_
    _ <- requireAuthId
    errors <- runDB $ validate entity
    if null errors
        then do
            jsonToRepJson $ emptyObject
        else jsonToRepJson $ object [ "errors" .= toJSON errors ]

putNoteR :: NoteId -> Handler RepJson
putNoteR key = do
    entity <- parseJsonBody_
    _ <- requireAuthId
    errors <- runDB $ validate entity
    if null errors
        then do
            runDB $ repsert key entity
        else jsonToRepJson $ object [ "errors" .= toJSON errors ]
    jsonToRepJson $ emptyObject

deleteNoteR :: NoteId -> Handler RepJson
deleteNoteR key = do
    _ <- requireAuthId
    runDB $ delete key
    jsonToRepJson $ emptyObject

postNoteManyR :: Handler RepJson
postNoteManyR = do
    entity <- parseJsonBody_
    _ <- requireAuthId
    errors <- runDB $ validate entity
    if null errors
        then do
            key <- runDB $ insert (entity :: Note)
            jsonToRepJson $ object [ "id" .= toJSON key ]
        else jsonToRepJson $ object [ "errors" .= toJSON errors ]
getNoteManyR :: Handler RepJson
getNoteManyR = do
    _ <- requireAuthId
    let filters = [] :: [Filter Note]
    let selectOpts = []
    entities <- runDB $ selectList (concat filters) selectOpts
    jsonToRepJson $ object [ "entities" .= toJSON entities ] 

getNoteR :: NoteId -> Handler RepJson
getNoteR key = do
    _ <- requireAuthId
    entity <- runDB $ get key
    jsonToRepJson $ toJSON entity

postPersonValidateR :: Handler RepJson
postPersonValidateR = do
    entity <- parseJsonBody_
    _ <- requireAuthId
    errors <- runDB $ validate entity
    if null errors
        then do
            jsonToRepJson $ emptyObject
        else jsonToRepJson $ object [ "errors" .= toJSON errors ]

putPersonR :: PersonId -> Handler RepJson
putPersonR key = do
    entity <- parseJsonBody_
    _ <- requireAuthId
    errors <- runDB $ validate entity
    if null errors
        then do
            runDB $ repsert key entity
        else jsonToRepJson $ object [ "errors" .= toJSON errors ]
    jsonToRepJson $ emptyObject

deletePersonR :: PersonId -> Handler RepJson
deletePersonR key = do
    _ <- requireAuthId
    runDB $ delete key
    jsonToRepJson $ emptyObject

postPersonManyR :: Handler RepJson
postPersonManyR = do
    entity <- parseJsonBody_
    _ <- requireAuthId
    errors <- runDB $ validate entity
    if null errors
        then do
            key <- runDB $ insert (entity :: Person)
            jsonToRepJson $ object [ "id" .= toJSON key ]
        else jsonToRepJson $ object [ "errors" .= toJSON errors ]
getPersonManyR :: Handler RepJson
getPersonManyR = do
    filters <- sequence [
        filterPersons
        ,
        do
            filter <- lookupGetParam "filter"
            if isJust filter
                then do
                    case json (fromJust filter) of
                        (Object o) -> do
                            return [] -- TODO: filter with o
                        _ -> invalidArgs [fromJust filter]
                else return []
        ]
    selectOpts <- [
        sortPersons
        ,
        do
            sortParam <- lookupGetParam "sort"
            if isJust sortParam
                then do
                    case json (fromJust sortParam) of
                        (Object o) -> do
                            return [] -- TODO: sort with o
                        _ -> invalidArgs [fromJust sortParam]
                else return []
        ]
    entities <- runDB $ selectList (concat filters) selectOpts
    sequence_ [logPersonGet entities]
    jsonToRepJson $ object [ "entities" .= toJSON entities ] 

getPersonR :: PersonId -> Handler RepJson
getPersonR key = do
    entity <- runDB $ get key
    errors <- sequence [personGetAllowed entity]
    if null errors
        then do
            sequence_ [logPersonGet key entity]
            jsonToRepJson $ toJSON entity
        else jsonToRepJson $ object [ "errors" .= toJSON errors ]
```

