module Git
  ( GitUrl,
    Error (..),
    --
    githubUrl,
    clone,
    localClone,
    update,
    tags,
    --
    hasLocalTag,
    hasLocalChangesSinceTag,
  )
where

import Data.ByteString.Char8 qualified as BS
import Data.Either qualified as Either
import Data.List qualified as List
import Gren.Package qualified as Pkg
import Gren.Version qualified as V
import Parse.Primitives qualified as Parser
import System.Directory (findExecutable)
import System.Exit qualified as Exit
import System.IO qualified as IO
import System.Process qualified as Process

data Error
  = MissingGit
  | FailedCommand (Maybe FilePath) [String] String
  | NoVersions FilePath

--

checkInstalledGit :: IO (Maybe FilePath)
checkInstalledGit =
  findExecutable "git"

putStrFlush :: String -> IO ()
putStrFlush str =
  IO.putStr str >> IO.hFlush IO.stdout

--

newtype GitUrl
  = GitUrl (String, String)

githubUrl :: Pkg.Name -> GitUrl
githubUrl pkg =
  GitUrl
    ( Pkg.toChars pkg,
      "https://github.com/" ++ Pkg.toUrl pkg ++ ".git"
    )

--

clone :: GitUrl -> FilePath -> IO (Either Error ())
clone (GitUrl (pkgName, gitUrl)) targetFolder = do
  maybeExec <- checkInstalledGit
  putStrFlush $ "Cloning " ++ pkgName ++ "... "
  case maybeExec of
    Nothing -> do
      putStrLn "Error!"
      return $ Left MissingGit
    Just git -> do
      let args = ["clone", "--bare", gitUrl, targetFolder]
      (exitCode, _, stderr) <-
        Process.readCreateProcessWithExitCode
          (Process.proc git args)
          ""
      case exitCode of
        Exit.ExitFailure _ -> do
          putStrLn "Error!"
          return $ Left $ FailedCommand Nothing ("git" : args) stderr
        Exit.ExitSuccess -> do
          putStrLn "Ok!"
          return $ Right ()

localClone :: FilePath -> V.Version -> FilePath -> IO (Either Error ())
localClone gitUrl vsn targetFolder = do
  maybeExec <- checkInstalledGit
  case maybeExec of
    Nothing ->
      return $ Left MissingGit
    Just git -> do
      let args =
            [ "clone",
              gitUrl,
              "--local",
              "-b",
              V.toChars vsn,
              "--depth",
              "1",
              targetFolder
            ]
      (exitCode, _, stderr) <-
        Process.readCreateProcessWithExitCode
          (Process.proc git args)
          ""
      case exitCode of
        Exit.ExitFailure _ -> do
          putStrLn "Error!"
          return $ Left $ FailedCommand Nothing ("git" : args) stderr
        Exit.ExitSuccess ->
          return $ Right ()

update :: Pkg.Name -> FilePath -> IO (Either Error ())
update pkg path = do
  maybeExec <- checkInstalledGit
  putStrFlush $ "Updating " ++ Pkg.toChars pkg ++ "... "
  case maybeExec of
    Nothing -> do
      putStrLn "Error!"
      return $ Left MissingGit
    Just git -> do
      let args = ["fetch", "-t"]
      (exitCode, _, stderr) <-
        Process.readCreateProcessWithExitCode
          ( (Process.proc git args)
              { Process.cwd = Just path
              }
          )
          ""
      case exitCode of
        Exit.ExitFailure _ -> do
          putStrLn "Error!"
          return $ Left $ FailedCommand (Just path) ("git" : args) stderr
        Exit.ExitSuccess -> do
          putStrLn "Ok!"
          return $ Right ()

tags :: FilePath -> IO (Either Error (V.Version, [V.Version]))
tags path = do
  maybeExec <- checkInstalledGit
  case maybeExec of
    Nothing ->
      return $ Left MissingGit
    Just git -> do
      let args = ["tag"]
      (exitCode, stdout, stderr) <-
        Process.readCreateProcessWithExitCode
          ( (Process.proc git args)
              { Process.cwd = Just path
              }
          )
          ""
      case exitCode of
        Exit.ExitFailure _ -> do
          return $ Left $ FailedCommand (Just path) ("git" : args) stderr
        Exit.ExitSuccess ->
          let tagList =
                map BS.pack $ lines stdout

              -- Ignore tags that aren't semantic versions
              versions =
                reverse $ List.sort $ Either.rights $ map (Parser.fromByteString V.parser (,)) tagList
           in case versions of
                [] -> return $ Left $ NoVersions path
                v : vs -> return $ Right (v, vs)

hasLocalTag :: V.Version -> IO (Either Error ())
hasLocalTag vsn = do
  maybeExec <- checkInstalledGit
  case maybeExec of
    Nothing ->
      return $ Left MissingGit
    Just git -> do
      let args = ["show", "--name-only", V.toChars vsn, "--"]
      (exitCode, _, stderr) <-
        Process.readCreateProcessWithExitCode
          (Process.proc git args)
          ""
      case exitCode of
        Exit.ExitFailure _ -> do
          return $ Left $ FailedCommand Nothing ("git" : args) stderr
        Exit.ExitSuccess ->
          return $ Right ()

hasLocalChangesSinceTag :: V.Version -> IO (Either Error ())
hasLocalChangesSinceTag vsn = do
  maybeExec <- checkInstalledGit
  case maybeExec of
    Nothing ->
      return $ Left MissingGit
    Just git -> do
      let args = ["diff-index", "--quiet", V.toChars vsn, "--"]
      (exitCode, _, stderr) <-
        Process.readCreateProcessWithExitCode
          (Process.proc git args)
          ""
      case exitCode of
        Exit.ExitFailure _ -> do
          return $ Left $ FailedCommand Nothing ("git" : args) stderr
        Exit.ExitSuccess ->
          return $ Right ()
