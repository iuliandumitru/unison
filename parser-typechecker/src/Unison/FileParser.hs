module Unison.FileParser where

-- import           Text.Parsec.Prim (ParsecT)
-- import qualified Unison.TypeParser as TypeParser
import Prelude hiding (readFile)
import           Unison.Parser
import Control.Applicative
import Data.Either (partitionEithers)
import Data.Map (Map)
import Unison.DataDeclaration (DataDeclaration(..))
import Unison.EffectDeclaration (EffectDeclaration(..))
import Unison.Parser (PEnv, penv0)
import Unison.Parsers (unsafeGetRight)
import Unison.Symbol (Symbol)
import Unison.Term (Term)
import Unison.TypeParser (S)
import Unison.Var (Var)
import qualified Data.Map as Map
import qualified Text.Parsec.Layout as L
import qualified Unison.Parser
import qualified Unison.Parsers as Parsers
import qualified Unison.Term as Term
import qualified Unison.TermParser as TermParser
import qualified Unison.TypeParser as TypeParser
import Control.Monad.Reader
import Data.Text.IO (readFile)
import System.IO (FilePath)
import qualified Data.Text as Text

data UnisonFile v = UnisonFile {
  dataDeclarations :: Map v (DataDeclaration v),
  effectDeclarations :: Map v (EffectDeclaration v),
  term :: Term v
} deriving (Show)

unsafeParseFile :: String -> PEnv -> UnisonFile Symbol
unsafeParseFile s env = unsafeGetRight $ parseFile "" s env

parseFile :: FilePath -> String -> PEnv -> Either String (UnisonFile Symbol)
parseFile filename s = Unison.Parser.run' (Unison.Parser.root file) s Parsers.s0 filename

parseFile' :: FilePath -> String -> Either String (UnisonFile Symbol)
parseFile' filename s = parseFile filename s penv0

unsafeReadAndParseFile' :: String -> IO (UnisonFile Symbol)
unsafeReadAndParseFile' = unsafeReadAndParseFile penv0

unsafeReadAndParseFile :: PEnv -> String -> IO (UnisonFile Symbol)
unsafeReadAndParseFile env filename = do
  txt <- readFile filename
  let str = Text.unpack txt
  pure $ unsafeGetRight (parseFile filename str env)

file :: Var v => Parser (S v) (UnisonFile v)
file = traced "file" $ do
  (dataDecls, effectDecls) <- traced "declarations" declarations
  local (`Map.union` environmentFor dataDecls effectDecls) $ do
    term <- TermParser.block
    pure $ UnisonFile dataDecls effectDecls term

environmentFor :: Map v (DataDeclaration v) -> Map v (EffectDeclaration v) -> PEnv
environmentFor ds es = Map.empty -- todo

declarations :: Var v => Parser (S v)
                         (Map v (DataDeclaration v),
                          Map v (EffectDeclaration v))
declarations = do
  declarations <- many ((Left <$> dataDeclaration) <|> Right <$> effectDeclaration)
  let (dataDecls, effectDecls) = partitionEithers declarations
  pure (Map.fromList dataDecls, Map.fromList effectDecls)


dataDeclaration :: Var v => Parser (S v) (v, DataDeclaration v)
dataDeclaration = traced "data declaration" $ do
  token_ $ string "type"
  (name, typeArgs) <- --L.withoutLayout "type introduction" $
    (,) <$> TermParser.prefixVar <*> traced "many prefixVar" (many TermParser.prefixVar)
  traced "=" . token_ $ string "="
  traced "vblock" $ L.vblockIncrement $ do
    constructors <- traced "constructors" $ sepBy (token_ $ string "|") dataConstructor
    pure $ (name, DataDeclaration typeArgs constructors)
  where
    dataConstructor = traced "data contructor" $ (,) <$> TermParser.prefixVar
                          <*> (traced "many typeLeaf" $ many TypeParser.valueTypeLeaf)

effectDeclaration :: Var v => Parser (S v) (v, EffectDeclaration v)
effectDeclaration = traced "effect declaration" $ do
  token_ $ string "effect"
  name <- TermParser.prefixVar
  typeArgs <- many TermParser.prefixVar
  token_ $ string "where"
  L.vblockNextToken $ do
    constructors <- sepBy L.vsemi constructor
    pure $ (name, EffectDeclaration typeArgs constructors)
  where
    constructor = (,) <$> (TermParser.prefixVar <* token_ (string ":")) <*> traced "computation type" TypeParser.computationType