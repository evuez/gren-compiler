module Type.Constrain.Declaration where

import Control.Monad
import Control.Applicative ((<$>))

import qualified Data.Map as Map

import qualified Type.Type as T
import qualified Type.Constrain.Expression as TcExpr
import qualified Type.Environment as Env

import SourceSyntax.Declaration
import qualified SourceSyntax.Location as SL
import qualified SourceSyntax.Literal as SL
import qualified SourceSyntax.Pattern as SP
import qualified SourceSyntax.Expression as SE
import qualified SourceSyntax.Type as ST


toExpr :: [Declaration t v] -> [SE.Def t v]
toExpr = concatMap toDefs

toDefs :: Declaration t v -> [SE.Def t v]
toDefs decl =
  case decl of
    Definition def -> [def]

    Datatype name tvars constructors -> concatMap toDefs constructors
      where
        toDefs (ctor, tipes) =
            let vars = take (length tipes) $ map (\n -> "_" ++ show n) [0..]
                loc = SL.none
                body = loc . SE.Data name $ map (loc . SE.Var) vars
            in  [ SE.TypeAnnotation ctor $
                      foldr ST.Lambda (ST.Data name $ map ST.Var tvars) tipes
                , SE.Def (SP.PVar ctor) $
                      foldr (\p e -> loc $ SE.Lambda p e) body (map SP.PVar vars)
                ]

    -- Type aliases must be added to an extended equality dictionary,
    -- but they do not require any basic constraints.
    TypeAlias _ _ _ -> []

    ImportEvent _ expr@(SL.L a b _) name tipe ->
        [ SE.TypeAnnotation name tipe
        , SE.Def (SP.PVar name) (SL.L a b $ SE.App (SL.L a b $ SE.Var "constant") expr) ]

    ExportEvent _ name tipe ->
        [ SE.TypeAnnotation name tipe ]

    -- no constraints are needed for fixity declarations
    Fixity _ _ _ -> []
