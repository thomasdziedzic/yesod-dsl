{
module DbLexer (lexer, tokenType, tokenLineNum, tokenColNum, Token(..), TokenType(..) ) where
}

%wrapper "posn"

$digit = 0-9
$alpha = [a-zA-Z]
$lower = [a-z]
$upper = [A-Z]
@stringWithoutSpecialChars = ($printable # [\" \\])*
@specialChars = [\\]$printable
@string = \" (@stringWithoutSpecialChars | @specialChars)* \"

tokens :-
	$white+	;
	"--".*	;
    \n ;
    @string { mkTvar (\s -> TString (stripQuotes s)) }
    \; { mkT TSemicolon } 
    \: { mkT TColon }
    \{ { mkT TLBrace }
    \} { mkT TRBrace }
    \[ { mkT TLBrack }
    \] { mkT TRBrack }
    \( { mkT TLParen }
    \) { mkT TRParen }
    \, { mkT TComma }
    \. { mkT TDot }
    "ref" { mkT TRef }
    "import" { mkT TImport }
    "document" { mkT TDoc }
    "interface" { mkT TIface  }
    "implements" { mkT TImplements }
    "unique" { mkT TUnique }
    "index" { mkT TIndex }
    "check" { mkT TCheck }
    "asc" { mkT TAsc }
    "desc" { mkT TDesc }
    "default" { mkT TDefault }
    "Word32" { mkT TWord32 }
    "Word64" { mkT TWord64 }
    "Int32" { mkT TInt32 }
    "Int64" { mkT TInt64 }
    "Text" { mkT TText }
    "Bool" { mkT TBool }
    "Double" { mkT TDouble }
    "Maybe" { mkT TMaybe }
    "Date" { mkT TDate }
    "Time" { mkT TTime }
    "DateTime" { mkT TDateTime }
    "ZonedTime" { mkT TZonedTime }
	$digit+ 		{ mkTvar (\s -> TInt (read s)) }
    $digit+ "." $digit+ { mkTvar (\s -> TFloat (read s)) }
	$lower [$alpha $digit \_ ]*  { mkTvar (\s -> TLowerId s) }
    $upper [$alpha $digit \_ ]*  { mkTvar (\s -> TUpperId s) }
    
{

data Token = Tk AlexPosn TokenType
    deriving (Show)
data TokenType = TSemicolon
               | TColon
               | TLBrace
               | TRBrace
               | TLParen
               | TRParen
               | TLBrack
               | TRBrack
               | TComma
               | TDot
               | TImport
               | TDoc
               | TImplements
               | TDefault
               | TIndex
               | TUnique
               | TIface
               | TString  String
               | TLowerId String
               | TUpperId String
               | TInt     Int
               | TFloat   Double
               | TRef 
               | TCheck
               | TWord32
               | TWord64
               | TInt32
               | TInt64
               | TText
               | TBool
               | TDouble
               | TMaybe
               | TTime
               | TDate
               | TDateTime
               | TZonedTime
               | TAsc
               | TDesc
	deriving (Show)

stripQuotes s = take ((length s) -2) (tail s)

mkT :: TokenType -> AlexPosn -> String -> Token
mkT t p s = Tk p t

mkTvar :: (String -> TokenType) -> AlexPosn -> String -> Token
mkTvar st p s = Tk p (st s)

tokenLineNum (Tk p _) = getLineNum p
tokenColNum (Tk p _)  = getColNum p
tokenType (Tk _ t) = t

getLineNum :: AlexPosn -> Int
getLineNum (AlexPn offset lineNum colNum) = lineNum

getColNum :: AlexPosn -> Int
getColNum (AlexPn offset lineNum colNum) = colNum

lexer = alexScanTokens 
}