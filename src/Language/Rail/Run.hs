-- | A direct interpreter for Rail programs.
module Language.Rail.Run
( Memory(..)
, emptyMemory
, Rail
, runRail
, runCommand
, run
, call
, compile
, runMemory
) where

import Data.ControlFlow
import Language.Rail.Base
import Language.Rail.Parse (getFunctions)
import qualified Data.Map as Map
import Control.Applicative
import Control.Monad.Trans.State
import Control.Monad.Trans.Error
import Control.Monad.Trans.Class (lift)
import Control.Monad.IO.Class (liftIO)
import System.IO (isEOF, hPutStr, stderr, hFlush, stdout)
import System.IO.Error (isEOFError)
import qualified Control.Exception (catch)
import Data.Void (absurd)

data Memory = Memory
  { stack     :: [Val]
  , variables :: Map.Map String Val
  , functions :: Map.Map String (Flow () Result Command)
  }

emptyMemory :: Memory
emptyMemory = Memory
  { stack     = []
  , variables = Map.empty
  , functions = Map.empty
  }

-- | An IO monad for executing Rail programs, combining 'ErrorT' (for crash
-- messages) with 'StateT' (for the stack and variables).
type Rail = StateT Memory (ErrorT String IO)

runRail :: Rail () -> Memory -> IO ()
runRail r mem = runErrorT (evalStateT r mem) >>= either (hPutStr stderr) return

err :: String -> Rail a
err = lift . throwError

setStack :: [Val] -> Rail ()
setStack stk = modify $ \mem -> mem { stack = stk }

setVariables :: Map.Map String Val -> Rail ()
setVariables vs = modify $ \mem -> mem { variables = vs }

getVar :: String -> Rail Val
getVar v = gets variables >>= \vs -> case Map.lookup v vs of
  Just x -> return x
  Nothing -> err $ "getVar: undefined variable: " ++ v

setVar :: String -> Val -> Rail ()
setVar v x = modify $ \mem ->
  mem { variables = Map.insert v x $ variables mem }

push :: Val -> Rail ()
push x = gets stack >>= setStack . (x :)

pop :: Rail Val
pop = gets stack >>= \stk -> case stk of
  [] -> err "pop: empty stack"
  x : xs -> setStack xs >> return x

popStr :: Rail String
popStr = pop >>= \v -> case v of
  Str s _ -> return s
  _ -> err "popStr: expected string"

popInt :: Rail Integer
popInt = pop >>= \v -> case v of
  Str _ (Just i) -> return i
  _ -> err "popInt: expected string"

popBool :: Rail Bool
popBool = popInt >>= \i -> case i of
  0 -> return False
  1 -> return True
  _ -> err "popBool: expected 0 or 1"

popPair :: Rail (Val, Val)
popPair = pop >>= \v -> case v of
  Pair x y -> return (x, y)
  _ -> err "popPair: expected pair"

runCommand :: Command -> Rail ()
runCommand c = case c of
  Val x -> push x
  Call fun -> gets functions >>= \funs -> case Map.lookup fun funs of
    Nothing -> err $ "call: undefined function " ++ fun
    Just sub -> call sub
  Add -> math (+)
  Sub -> math (-)
  Mult -> math (*)
  Div -> math div
  Rem -> math mod
  EOF -> liftIO isEOF >>= push . toVal
  Output -> popStr >>= liftIO . putStr >> liftIO (hFlush stdout)
  Input -> liftIO getChar' >>= \mc -> case mc of
    Just ch -> push $ toVal [ch]
    Nothing -> err "input: end of file"
  Equal -> liftA2 equal pop pop >>= push . toVal
  Greater -> liftA2 (<) popInt popInt >>= push . toVal
  -- (<) because flipped args: we're asking (2nd top of stack) > (top of stack)
  Underflow -> gets stack >>= push . toVal . length
  Type -> pop >>= \v -> push $ toVal $ case v of
    Str _ _ -> "string"
    Nil -> "nil"
    Pair _ _ -> "list"
  Cons -> liftA2 (flip Pair) pop pop >>= push
  Uncons -> popPair >>= \(x, y) -> push x >> push y
  Size -> popStr >>= push . toVal . length
  Append -> liftA2 (flip (++)) popStr popStr >>= push . toVal
  Cut -> do
    i <- fmap fromIntegral popInt
    s <- popStr
    if 0 <= i && i <= length s
      then case splitAt i s of
        (x, y) -> push (toVal x) >> push (toVal y)
      else err "cut: string index out of bounds"
  Push var -> getVar var >>= push
  Pop var -> pop >>= setVar var

-- | Like 'getChar', but catches EOF exceptions and returns Nothing.
getChar' :: IO (Maybe Char)
getChar' = Control.Exception.catch (fmap Just getChar) $ \e ->
  if isEOFError e then return Nothing else ioError e

math :: (Integer -> Integer -> Integer) -> Rail ()
math op = liftA2 (flip op) popInt popInt >>= push . toVal

equal :: Val -> Val -> Bool
equal (Str _ (Just x)) (Str _ (Just y)) = x == y
equal x y = x == y

-- | Runs a piece of code. Does not create a new scope.
run :: Flow () Result Command -> Rail ()
run g = case g of
  x :>> c       -> runCommand x >> run c
  Branch () x y -> popBool >>= \b -> run $ if b then y else x
  Continue c    -> absurd c
  End e         -> case e of
    Return -> return ()
    Boom -> popStr >>= err
    Internal s -> err s

-- | Runs a function, which creates a new scope for the length of the function.
call :: Flow () Result Command -> Rail ()
call sub = gets variables >>= \vs ->
  setVariables Map.empty >> run sub >> setVariables vs

compile :: String -> Memory
compile str = emptyMemory
  { functions = Map.fromList $ map (mapSnd flow) $ getFunctions str }
  where mapSnd f (x, y) = (x, f y)

runMemory :: Memory -> IO ()
runMemory = runRail $ run $ Call "main" :>> End Return
