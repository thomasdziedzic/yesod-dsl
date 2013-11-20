{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ConstraintKinds #-}
{-# OPTIONS_GHC -fno-warn-overlapping-patterns #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
module Handler.Example.RouteBlogposts where
import Handler.Example.Enums
import Handler.Example.Esqueleto
import Handler.Example.Internal
import Prelude
import Database.Esqueleto
import Database.Esqueleto.Internal.Sql (unsafeSqlBinOp)
import qualified Database.Persist as P
import Database.Persist.TH
import Yesod.Auth (requireAuth, requireAuthId, YesodAuth, AuthId, YesodAuthPersist)
import Yesod.Core
import Yesod.Persist (runDB, YesodPersist, YesodPersistBackend)
import Data.Aeson ((.:), (.:?), (.!=), FromJSON, parseJSON, decode)
import Data.Aeson.TH
import Data.Int
import Data.Word
import Data.Time
import Data.Text.Encoding (encodeUtf8)
import Data.Typeable (Typeable)
import qualified Data.Attoparsec as AP
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as AT
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe
import qualified Data.Text.Read
import qualified Data.Text as T
import Data.Text (Text)
import qualified Data.List as DL
import Control.Monad (mzero)
import Control.Monad.Trans.Resource (runResourceT)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import qualified Network.HTTP.Conduit as C
import qualified Network.Wai as W
import Data.Conduit.Lazy (lazyConsume)
import Network.HTTP.Types (status200, status400, status403, status404)
import Blaze.ByteString.Builder.ByteString (fromByteString)
import Control.Applicative ((<$>), (<*>))  
import qualified Data.HashMap.Lazy as HML
import qualified Data.HashMap.Strict as HMS

getBlogpostsR :: forall master. (ExampleValidation master, 
    YesodAuthPersist master,
    KeyEntity (AuthId master) ~ User,
    YesodPersistBackend master ~ SqlPersistT)
    => HandlerT Example (HandlerT master IO) A.Value
getBlogpostsR  = do
    filterParam_blogPostName <- lookupGetParam "blogPostName"
    defaultFilterParam <- lookupGetParam "filter"
    let defaultFilterJson = (maybe Nothing (decode . LBS.fromChunks . (:[]) . encodeUtf8) defaultFilterParam) :: Maybe [FilterJsonMsg]
    defaultSortParam <- lookupGetParam "sort"
    let defaultSortJson = (maybe Nothing (decode . LBS.fromChunks . (:[]) . encodeUtf8) defaultSortParam) :: Maybe [SortJsonMsg]
    defaultOffsetParam <- lookupGetParam "start"
    defaultLimitParam <- lookupGetParam "limit"
    let defaultOffset = (maybe Nothing fromPathPiece defaultOffsetParam) :: Maybe Int64
    let defaultLimit = (maybe Nothing fromPathPiece defaultLimitParam) :: Maybe Int64
    let baseQuery limitOffsetOrder = from $ \(bp  `InnerJoin` p) -> do
        on ((p ^. UserId) ==. (bp ^. BlogPostAuthorId))
        let bpId' = bp ^. BlogPostId

        _ <- if limitOffsetOrder
            then do 
                offset 0
                limit 1000
                case defaultSortJson of 
                    Just xs -> mapM_ (\sjm -> case sortJsonMsg_property sjm of
                            "authorId" -> case (sortJsonMsg_direction sjm) of 
                                "ASC"  -> orderBy [ asc (bp  ^.  BlogPostAuthorId) ] 
                                "DESC" -> orderBy [ desc (bp  ^.  BlogPostAuthorId) ] 
                                _      -> return ()
                            "content" -> case (sortJsonMsg_direction sjm) of 
                                "ASC"  -> orderBy [ asc (bp  ^.  BlogPostContent) ] 
                                "DESC" -> orderBy [ desc (bp  ^.  BlogPostContent) ] 
                                _      -> return ()
                            "time" -> case (sortJsonMsg_direction sjm) of 
                                "ASC"  -> orderBy [ asc (bp  ^.  BlogPostTime) ] 
                                "DESC" -> orderBy [ desc (bp  ^.  BlogPostTime) ] 
                                _      -> return ()
                            "name" -> case (sortJsonMsg_direction sjm) of 
                                "ASC"  -> orderBy [ asc (bp  ^.  BlogPostName) ] 
                                "DESC" -> orderBy [ desc (bp  ^.  BlogPostName) ] 
                                _      -> return ()
                            "authorFirstName" -> case (sortJsonMsg_direction sjm) of 
                                "ASC"  -> orderBy [ asc (p  ^.  UserFirstName) ] 
                                "DESC" -> orderBy [ desc (p  ^.  UserFirstName) ] 
                                _      -> return ()
                            "authorLastName" -> case (sortJsonMsg_direction sjm) of 
                                "ASC"  -> orderBy [ asc (p  ^.  UserLastName) ] 
                                "DESC" -> orderBy [ desc (p  ^.  UserLastName) ] 
                                _      -> return ()
                
                            _ -> return ()
                        ) xs
                    Nothing -> orderBy [ asc (bp ^. BlogPostName) ]

                case defaultOffset of
                    Just o -> offset o
                    Nothing -> return ()
                case defaultLimit of
                    Just l -> limit (min 10000 l)
                    Nothing -> return ()
                 
            else return ()
        case defaultFilterJson of 
            Just xs -> mapM_ (\fjm -> case filterJsonMsg_field_or_property fjm of
                "firstName" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (p  ^.  UserFirstName) (val v) 
                    _        -> return ()
                "lastName" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (p  ^.  UserLastName) (val v) 
                    _        -> return ()
                "age" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (p  ^.  UserAge) (just (val v)) 
                    _        -> return ()
                "name" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (p  ^.  UserName) (val v) 
                    _        -> return ()
                "deletedVersionId" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (p  ^.  UserDeletedVersionId) (just (val v)) 
                    _        -> return ()
                "authorId" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (bp  ^.  BlogPostAuthorId) (val v) 
                    _        -> return ()
                "content" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (bp  ^.  BlogPostContent) (val v) 
                    _        -> return ()
                "time" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (bp  ^.  BlogPostTime) (val v) 
                    _        -> return ()
                "name" -> case (fromPathPiece $ filterJsonMsg_value fjm) of 
                    (Just v) -> where_ $ defaultFilterOp (filterJsonMsg_comparison fjm) (bp  ^.  BlogPostName) (val v) 
                    _        -> return ()

                _ -> return ()
                ) xs
            Nothing -> return ()  
        case getDefaultFilter filterParam_blogPostName defaultFilterJson "blogPostName" of
            Just localParam -> do 

                where_ $ ((bp ^. BlogPostName) `ilike` (((val "%")) ++. (((val (localParam :: Text))) ++. ((val "%"))))) ||. (((p ^. UserFirstName) `ilike` (((val "%")) ++. (((val (localParam :: Text))) ++. ((val "%"))))) ||. ((p ^. UserLastName) `ilike` (((val "%")) ++. (((val (localParam :: Text))) ++. ((val "%"))))))
            Nothing -> return ()
        return (bp ^. BlogPostId, bp ^. BlogPostAuthorId, bp ^. BlogPostContent, bp ^. BlogPostTime, bp ^. BlogPostName, p ^. UserFirstName, p ^. UserLastName)
    count <- lift $ runDB $ select $ do
        baseQuery False
        let countRows' = countRows
        orderBy []
        return $ (countRows' :: SqlExpr (Database.Esqueleto.Value Int))
    results <- lift $ runDB $ select $ baseQuery True
    return $ A.object [
        "totalCount" .= (T.pack $ (\(Database.Esqueleto.Value v) -> show (v::Int)) (head count)),
        "result" .= (toJSON $ map (\row -> case row of
                ((Database.Esqueleto.Value f1), (Database.Esqueleto.Value f2), (Database.Esqueleto.Value f3), (Database.Esqueleto.Value f4), (Database.Esqueleto.Value f5), (Database.Esqueleto.Value f6), (Database.Esqueleto.Value f7)) -> A.object [
                    "id" .= toJSON f1,
                    "authorId" .= toJSON f2,
                    "content" .= toJSON f3,
                    "time" .= toJSON f4,
                    "name" .= toJSON f5,
                    "authorFirstName" .= toJSON f6,
                    "authorLastName" .= toJSON f7                                    
                    ]
                _ -> A.object []
            ) results)
       ]
postBlogpostsR :: forall master. (ExampleValidation master, 
    YesodAuthPersist master,
    KeyEntity (AuthId master) ~ User,
    YesodPersistBackend master ~ SqlPersistT)
    => HandlerT Example (HandlerT master IO) A.Value
postBlogpostsR  = do
    authId <- lift $ requireAuthId
    yReq <- getRequest
    let wReq = reqWaiRequest yReq
    jsonResult <- parseJsonBody
    jsonBody <- case jsonResult of
         A.Error err -> sendResponseStatus status400 $ A.object [ "message" .= ( "Could not decode JSON object from request body : " ++ err) ]
         A.Success o -> return o
    jsonBodyObj <- case jsonBody of
        A.Object o -> return o
        v -> sendResponseStatus status400 $ A.object [ "message" .= ("Expected JSON object in the request body, got: " ++ show v) ]
    attr_content <- case HML.lookup "content" jsonBodyObj of 
        Just v -> case A.fromJSON v of
            A.Success v' -> return v'
            A.Error err -> sendResponseStatus status400 $ A.object [
                    "message" .= ("Could not parse value from attribute content in the JSON object in request body" :: Text),
                    "error" .= err
                ]
        Nothing -> sendResponseStatus status400 $ A.object [
                "message" .= ("Expected attribute content in the JSON object in request body" :: Text)
            ]
    attr_name <- case HML.lookup "name" jsonBodyObj of 
        Just v -> case A.fromJSON v of
            A.Success v' -> return v'
            A.Error err -> sendResponseStatus status400 $ A.object [
                    "message" .= ("Could not parse value from attribute name in the JSON object in request body" :: Text),
                    "error" .= err
                ]
        Nothing -> sendResponseStatus status400 $ A.object [
                "message" .= ("Expected attribute name in the JSON object in request body" :: Text)
            ]
    __currentTime <- liftIO $ getCurrentTime
    runDB_result <- lift $ runDB $ do
        e1 <- do
    
            return $ BlogPost {
                            blogPostAuthorId = authId
                    
                    ,
                            blogPostContent = attr_content
                    
                    ,
                            blogPostTime = __currentTime
                    
                    ,
                            blogPostName = attr_name
                    
     
                }
        vErrors <- lift $ validate e1
        case vErrors of
            xs@(_:_) -> sendResponseStatus status400 (A.object [ 
                        "message" .= ("Entity validation failed" :: Text),
                        "errors" .= toJSON xs 
                    ])
            _ -> return ()
        P.insert (e1 :: BlogPost)
        return A.Null
    return $ runDB_result
