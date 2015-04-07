{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import Language.Haskell.Exts
import Language.Haskell.Exts.Pretty
import Data.List
import System.Directory
import System.FilePath
import System.Posix.Files
import Control.Monad
import Control.Applicative ((<$>))
import Control.Exception

import System.Console.ANSI

main = do
    modules <- findAllModules
    mapM_ qa modules
  where qa file = do
            printHeader ("==== " ++ file)
            content <- readFile file
            let mexts = readExtensions content
            case mexts of
                Nothing        -> printError "failed to parsed extensions"
                Just (_, exts) -> qaExts file content exts

        qaExts file content exts = do
            printInfo "extensions" (intercalate ", " $ map show exts)

            let mode = defaultParseMode { parseFilename = file, extensions = exts }

            case parseModuleWithMode mode content of
                ParseFailed srcLoc s -> printError ("failed to parse module: " ++ show srcLoc ++ " : " ++ s)
                ParseOk mod          -> do
                    let imports = getModulesImports mod
                    printInfo "modules" (intercalate ", "  (map (prettyPrint . importModule) imports))

                    let useSystemIOUnsafe = elem (ModuleName "System.IO.Unsafe") (map importModule imports)
                    when useSystemIOUnsafe $ printWarningImport "Crypto.Internal.Compat" "System.IO.Unsafe"

        printHeader s =
            setSGR [SetColor Foreground Vivid Green] >> putStrLn s >> setSGR []
        printInfo k v =
            setSGR [SetColor Foreground Vivid Blue] >> putStr k >> setSGR [] >> putStr ": " >> putStrLn v
        printError s =
            setSGR [SetColor Foreground Vivid Red] >> putStrLn s >> setSGR []

        printWarningImport expected actual =
            setSGR [SetColor Foreground Vivid Yellow] >> putStrLn ("warning: use " ++ show expected ++ " instead of " ++ actual) >> setSGR []

        getModulesImports (Module _ _ _ _ _ imports _) = imports

findAllModules :: IO [FilePath]
findAllModules = dirTraverse "Crypto" fileCallback dirCallback []
  where
        fileCallback a m = return (if isSuffixOf ".hs" m then (m:a) else a)
        dirCallback a d
            | isSuffixOf "/.git" d = return (False, a)
            | otherwise            = return (True, a)

-- | Traverse directories and files starting from the @rootDir
dirTraverse :: FilePath
            -> (a -> FilePath -> IO a)
            -> (a -> FilePath -> IO (Bool, a))
            -> a
            -> IO a
dirTraverse rootDir fFile fDir a = loop a rootDir
  where loop a dir = do
            content <- try $ getDir dir
            case content of
                Left (exn :: SomeException) -> return a
                Right l  -> foldM (processEnt dir) a l
        processEnt dir a ent = do
            let fp = dir </> ent
            stat <- getSymbolicLinkStatus fp
            case (isDirectory stat, isRegularFile stat) of
                (True,_)     -> do (process,a') <- fDir a fp
                                   if process
                                      then loop a' fp
                                      else return a'
                (False,True)  -> fFile a fp
                (False,False) -> return a
        getDir dir = filter (not . flip elem [".",".."]) <$> getDirectoryContents dir
