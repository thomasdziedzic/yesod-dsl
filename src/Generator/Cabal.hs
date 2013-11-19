module Generator.Cabal (syncCabal) where
import AST
import Distribution.PackageDescription
import Distribution.ModuleName
import Distribution.PackageDescription.Parse
import Distribution.PackageDescription.PrettyPrint
import Distribution.Package
import Data.Maybe (fromMaybe)
import System.Directory
import Distribution.Verbosity
import System.FilePath.Posix
import Data.List
import Generator.Routes
import SyncFile
stripGenerated :: Module -> [ModuleName] -> [ModuleName]
stripGenerated m mods = [ mn | mn <- mods, 
          not $("Handler." ++ (fromMaybe "" $ modName m)) `isPrefixOf` (mnToString mn) ]
    where mnToString mn = intercalate "." (components mn)            

generatedMods :: Module -> [ModuleName]
generatedMods m = map fromString $ [pfx, pfx ++ ".Internal", pfx ++ ".Enums", pfx ++ ".Routes"]
                ++ [pfx ++ "." ++ (routeModuleName r) | r <- modRoutes m ]
    where pfx = "Handler." ++ (fromMaybe "" $ modName m)
modifyDesc :: Module -> GenericPackageDescription -> GenericPackageDescription
modifyDesc m d = d {
        condLibrary = (condLibrary d) >>= modifyCtree
    }
    where 
        modifyCtree ctree = Just $ ctree {
            condTreeData = modifyLib (condTreeData ctree)
        }
        modifyLib l = l {
            exposedModules = modifyExposed (exposedModules l)            
        }
        modifyExposed mods = stripGenerated m mods ++ generatedMods m

syncCabal :: FilePath -> Module -> IO ()
syncCabal path' m = do
    let path = addExtension (dropExtension path') ".cabal"
    e <- doesFileExist path
    if e 
        then do
            desc <- readPackageDescription verbose path
            
            let content = showGenericPackageDescription (modifyDesc m desc)
            syncFile path content

        else return ()


    
    
