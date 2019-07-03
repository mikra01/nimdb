# MIT license; see license file for details

import db_common
export db_common
import options

type
  DbConnectionProperty* = tuple[key: string, val: string]
  ## future use for the 'open' procs
  DbTableColumnMetaData* = object of RootObj
  RCode* = tuple[vendorcode: int, errStr: string]
    ## generic returncode resultcontainer. 
    ## the vendorcode can be evaluated with 
    ## the 'eval' templates

  DbConn* = object
    ## the database-connection needed for executing/preparing statements
  PreparedStatement* = object
    ## a prepared statement for specific query
    ## the statement could be cached by the application to avoid
    ## parsing by the db
  ResultSet* = object
    ## needed to retrieve the results from the backend

proc `$`* (p: var RCode): string =
  ## get  the string representation of RCode
  result = "vendorcode: " & $p.vendorcode & " " & p.errStr

template copyCstrToNewNimStr*(out_result: var string,
                               statement_emit_cstring: untyped) {.dirty.} =
  ## helper template to copy a backends string to a nimstring
  var str: cstring = statement_emit_cstring
  out_result = newString(str.len)
  if str.len > 0:
    copyMem(addr(out_result[0]), str, out_result.len)

# unfortunately strutils does not support toHex(seq[byte])
# so we need this helper
const hChars = "0123456789ABCDEF"

proc hex2Str*(par: var openArray[byte]): string =
  result = newString(2 + ((par.len) shl 1)) # len mul 2 plus 2 extra chars
  result[0] = '0'
  result[1] = 'x'
  for i in countup(0, par.len-1):
    result[2 + cast[int](i shl 1)] =
      hChars[cast[int](par[i] shr 4)] # process hs nibble
    result[3 + cast[int](i shl 1)] =
      hChars[cast[int](par[i] and 0xF)] # process ls nibble

proc open*(props: var seq[DbConnectionProperty], outpar: var RCode): DbConn =
  ## not implemented
  # TODO: implement
  discard

proc close*(db: DbConn, outpar: var RCode) {.tags: [DbEffect].} =
  ## closes the database connection.
  discard

