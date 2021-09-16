#  MIT license; see license file for details
## this module is a new rdbms-api for sqlite3. 
## 
## main changes compared to the classic (db_sqlite) API:
## * no exceptions  
## * faster (for a speed comparison please take a look at the examples directory)  
## * transaction- and cleanup templates
## * the prepared statement is exposed to the API so it´s possible
##   to bulk load huge datasets into the database
## * bulk row bindings per object or raw 
## * huge ResultSets can be consumed with a stream-like API
## * binding and fetching is typed (the API comes in two 
##   flavours : Option and nim-type(integer,float64, string and blob)  ) 
## * text and blob-types can be consumed by pointer (raw) or 
##   by the nim-types string and seq[byte]
## * backup-interface 
## * metadata api (column-names and columntypes of tables can be retrieved) 
## * db_sqlite importable without symbol clash
##
## Note about string- and blob-handling: 
## this comes in two flavours: traced and untraced.
## The traced version (which should be sufficient for most use cases) copies the blob/varchar
## immediately into a seq[byte]/nimstring while reading. The unmanaged version only provides
## the backend pointer and length; the content must copied (before consuming the resultSet's
## next row ) into the application domain.
##
## storing into db is straightforward; the optional destructor callback is provided for both flavours.
## if the destructor callback is not used the object/ptr should stay valid till the transaction ends.
##  
## no implicit type conversion is performed - the caller needs to take care
## of the types expected. If the type does not match, sqlite tries a implicit type
## conversion. Further reading: https://www.sqlite.org/datatype3.html
##
## in-memory-operation: 
## keep in mind that each open(::inmemory::) opens a new
## database unless in shared cache mode - if you like to use a 
## connectionpool be sure that the shared cache of sqlite3 is activated (untested)
##
## At the moment no examples are within this doc. for examples please take a look at the
## examples subdirectory.  
## the entire source was compiled with compiler version 0.19.9 /
## git hash: 28a83a838821cbe3efc8ddd412db966ca164ef5c
##
##
# implementation hints:
# the future plan is to provide a subset of generic procs 
# and a more vendor specific API. Remember (unless you are doing (theoretically) only
# ansi compilant sql ) the query itself is in most cases vendor specific.    
#
# not everything of the sqlite3-API is wrapped (execution cancelation, busy timeout,
# UDF, incremental blob API, custom collations )
#
# proc names with the sqlite3 prefix are direct wrapper calls (nimdb_sqlite3w).
# For consistency with the other drivers (postgresql,odbc) a prepared statement call
# returns a ResultSet type which is an alias for the PreparedStatement. 
# all out parameter names of the procs are prefixed with 'out_'
#
import sequtils, options

import ../nimdb_common
import nimdb_sqlite3w

type
  DbConn* = PSqlite3 
  PreparedStatement* = nimdb_sqlite3w.Pstmt
    ## sqlite3's preparedStatement handle 
  ResultSet* = PreparedStatement 
    ## needed to obtain the backend's results on a 'per row' base.
    ## update is not supported
  RCode* = nimdb_common.RCode
     ## backends returncode collector. 
     ## the vendorcode can be evaluated with 
     ## the 'eval' templates (evalBindError/evalHasError/hasRows)

  SQLite3ProgressHandlerCb = proc (para1: pointer): int32{.cdecl.}
    ## if the parameter returned is non-zero then the operation was canceled
    ## by the database
  SQLite3BusyHandlerCb = proc (para1: pointer, para2: int32): int32{.cdecl.}
    ## busy handler callback see sqlite3_busy_handler
  SQLite3ExecuteCb = proc ( p1: pointer, numcols: int32, fields,
                            colnames: cstringArray) : int32 {.cdecl.}
    ## the callback for executing a query without preparedStatement
  SQLite3UnbindCb = Tbind_destructor_func
    ## called by sqlite3 to release the string/blob ptr

const 
  NimDbForceRollback_ERROR = -99.int
    ## internal errorcode to perform a rollback without exception 

template evalHasError*( rc : var RCode ) : bool = 
  ## template which checks for error return codes. for instance 
  ## SQLITE_BUSY (obj-lock) will be handled as an error
  rc.vendorcode != SQLITE_OK and 
    rc.vendorcode != SQLITE_ROW and 
    rc.vendorcode != SQLITE_DONE and 
    rc.vendorcode != SQLITE_INTERRUPT

template forceRollback*( rc : var RCode ) =
  ## usable within a transaction to force a non technical rollback without
  ## throwing an exception
  rc.vendorcode = NimDbForceRollback_ERROR

template collectMsgAndDoIfError(rc : var RCode, 
                                   db : DbConn, 
                                  body : untyped ) =
  ## evaluates for error.  if so the error message is collected
  ## into rc and the body is executed 
  if evalHasError(rc):
    rc.errStr = $errmsg(db)
    body

template collectMsgAndDoIfError( rc : var RCode, 
                                  ps: PreparedStatement, 
                                  body : untyped) =
  ## evaluates for error. if true the error message is collected and the body
  ## is executed 
  bind nimdb_sqlite3w.sqlite3_db_handle
  if evalHasError(rc):
    rc.errStr = $errmsg(sqlite3_db_handle(ps) )
    body

template collectMsgAndDoIfErrorElse( rc : var RCode, 
                                     db : DbConn, 
                                     body_err : untyped, 
                                     body_ok : untyped) =
  ## evaluates for error. if true the error message is collected and the body_err
  ## is executed else body_ok is executed 
  if evalHasError(rc):
    rc.errStr = $errmsg(db) # ucs does not work here
    body_err
  else:
    body_ok  

template collectVendorRCode(rc : var RCode , 
                            statement_emit_vendorcode : untyped ) =
  ## the vendorcode is collected into the field vendorcode of the RCode type
  rc.vendorcode = statement_emit_vendorcode

template hasRows*( ec : var RCode) : bool =
  ## true if the backend returned SQLITE_ROW
  ec.vendorcode == SQLITE_ROW

template evalBindError*(vendorcode : int) : bool =
  ## returns true if a bind error happened
  # eval after bind operation for varchar and blob.
  # only these types could emit the following errors: 
  # SQLITE_NOMEM/SQLITE_TOOBIG/SQLITE_RANGE
  vendorcode != SQLITE_NOMEM and 
    vendorcode != SQLITE_TOOBIG and 
    vendorcode != SQLITE_RANGE

template fetchErrcode*( dbconn: DbConn) : int =
  ## fetches the errorcode according to the vendor spec 
  ## only needed if the raw-type bind/fetching procs are used
  errcode(dbconn)  

template fetchErrcode*( ps : PreparedStatement) : int =
  ## fetches the errorcode according to the vendors spec 
  ## only needed if the raw bind/fetching procs are used
  fetchErrcode(ps.sqlite3_db_handle)

template prepareNextRow*( rs : ResultSet ,  r : var RCode) =
  ## raw API: invokes step() of the query-interface. the vendorcode is set.
  bind nimdb_sqlite3w.step
  r.vendorcode = step(rs)

proc getResultSet*( ps : PreparedStatement , 
                    out_rc : var RCode) : ResultSet {.inline.} =
  ## the resultSet is automatically advanced to the first row ready to read.
  ## If the out_columnCount is 0, the statement was no select statement or
  ## already returned SQLITE_DONE. The PreparedStatement performs a 'wind-back'
  ## on each call of getResultSet (query is re-executed)
  if not (ps.sqlite3_stmt_busy != 0): 
    out_rc.collectVendorRCode:
      step(ps)
  else:
      discard reset(ps) # wind back 
      out_rc.collectVendorRCode:
        step(ps) # and re execute query

  result = ps  # sqlite3's row-fetcher is the prepared statement

template resetPreparedStatement*(ps : PreparedStatement, out_rc : var RCode)  =
  ## reset the preparedStatement ready to re-execute.
  ## needed to reset the prepared statement for re-execute later on.
  bind reset
  bind clear_bindings
  collectVendorRCode(out_rc):
    reset(ps)
  if not evalHasError(out_rc):
    collectVendorRCode(out_rc):
      clear_bindings(ps)

proc sqlite3VersionStr*() : string = 
  ## debugging purpose. returns the version and libversion_number as string
  let libv : int32 = libversion_number()
  var intstr : string 
  copyCstrToNewNimStr(intstr,version()) 
  result = intstr & " libversion_no: " & $libv

proc interrupt*(conn : DbConn) =
  ## interrupts the current running query. Rollback is
  ## executed for a insert/update/delete.
  ## call this from a different thread (see sqlite3_busy_handler)
  # TODO: check how sqlite3 resolves a deadlock
  nimdb_sqlite3w.interrupt(conn)

proc open*(filename : string, 
               user : string, 
           password : string,
              out_param : var RCode, 
          out_param_ext : var int,
              flags : int = nimdb_sqlite3w.SQLITE_OPEN_READWRITE or 
                            nimdb_sqlite3w.SQLITE_OPEN_CREATE 
             ) : DbConn  {.
  tags: [DbEffect].} =
  ## Opens a connection to the specified database.  Utilizes the 
  ## sqlite open_v2 interface. Parameters 'user' and 'password' are unused.
  ## if SQLITE_CANTOPEN is returned the out_param_ext is set 
  ## by the wrapper call 'sqlite3_system_errno'.
  ##
  ## The filename can be specified in a uri-style format. 
  ## see: 
  ## * https://www.sqlite.org/uri.html#uri_filenames_in_sqlite
  # TODO: uri-example:
  #
  # .. code-block:: nim
  #    import src/driver/sqlite3/nimdb_sqlite3
  #    
  #    var errc : RCode = (vendorcode: 0.int , errStr: "")
  #    var syserrc : int
  #    let db = open(":memory:", "", "",errc,syserrc)
  #
  #    errc.collectMsgAndDoIfErrorElse(db) do:
  #      echo $errc
  #      quit(errc.vendorcode)
  #    do:
  #      discard   
  #
  #
  out_param_ext = 0
  out_param.vendorcode = sqlite3_open_v2(filename,result,flags,nil)
  out_param.collectMsgAndDoIfError(result):
    if out_param.vendorcode == SQLITE_CANTOPEN:
      out_param_ext = sqlite3_system_errno(result)

proc openReadonly*(filename:string, user:string, password:string,
  out_param : var RCode, out_param_ext : var int): DbConn {.
  tags: [DbEffect].} =
  ## vendor specific operation.
  ## Opens a database in readonly mode. 
  ## The database file is opened  readonly by sqlite3 at os file-level.
  ## The zVfsName is internally nil (default vfs)
  result = open(filename,user,password,out_param,out_param_ext,
                             nimdb_sqlite3w.SQLITE_OPEN_READONLY) 

proc close*(db: DbConn, out_par : var RCode ) {.tags: [DbEffect].} =
  ## closes the database connection.
  out_par.vendorcode = nimdb_sqlite3w.close(db) 
  out_par.collectMsgAndDoIfError(db):
    discard

proc dumpDbTo*(srcConn : DbConn, dstConn : DbConn, 
               outpar : var RCode,
               srcDbName : string = "main" , 
               dstDbName : string = "main" )  =
  ## Vendor specific operation.
  ## Performs a hot database backup (snapshot) from the src to destionation db.
  ##
  ## This proc call blocks till the entire database is copied completely.
  ## The dstConn is not allowed to have any pending transactions open.
  ##
  ## The src and destination db could be both of type in memory or file based.
  ## just ensure that the dest db is completely empty
  ## and the page_size is equal to the src db (see pragma page_size)
  ##
  ## for further reading please look at https://www.sqlite.org/backup.html
  var pBackup : PDbSqlite3Backup

  pBackup = dstConn.sqlite3_backup_init(dstDbName,srcConn,srcDbName)
  
  if not pBackup.isNil:
    # TODO: backup with pagecount (iterator)
    out_par.vendorcode = sqlite3_backup_step(pBackup,-1.int)
    discard sqlite3_backup_finish(pBackup)
  
  if evalHasError(out_par):
    out_par.errStr = $errmsg(dstConn)
      
proc `$`* ( p : var Pstmt ): string =
  ## Gets the normalized string representation out of the prepared statement.
  ## Could be used as a key for caching the statements in a map
  copyCstrToNewNimStr(result,sqlite3_normalized_sql(p))

proc `$`*(par: RCode): string =
  ## debugging support
  ## converts the driver returncode into a string representation    \
  result = "SQLITECODE: " & $par.vendorcode & " " & par.errStr

# TODO: review binding and fetching procs. Int32/Int64/float32/float64 is hacky
# and should not exposed to the API

proc bindInt32*( ps : PreparedStatement, paramIdx: int,
  val : int32 ) : int {.inline.} =   # seems to persist a 32bit value but needs eval
  ## Binds a 32bit integer. no null handling is performed
  result = bind_int( ps, paramIdx.int32, val )

proc bindInt32*( ps : PreparedStatement, paramIdx: int,
                   val : Option[int32]) : int {.inline.} =   
  ## Binds a 32bit integer to the specified paramIndex. performs null handling.
  ## The return value is the sqlite returncode which 
  ## can be evaluated by the evalHasError/evalBindError template
  if val.isNone:
    result = bind_null(ps, paramIdx.int32)   
  else:
    result = bind_int64( ps, paramIdx.int32, unsafeGet(val) )

proc bindInt64*( ps : PreparedStatement, paramIdx: int,
    val : int64 ) : int  {.inline.} =   
  ## Binds a 64bit integer to thespecified paramIndex.
  ## this version performs no null handling and is suitable for bulk update/insert.
  ## the return value is the sqlite returncode which can be 
  ## evaluated by the evalHasError/evalBindError template
  result = bind_int64(ps, paramIdx.int32, val)

proc bindInt64*( ps : PreparedStatement, paramIdx: int,
  val : Option[int64]) : int {.inline.} =   
  ## Binds a 64bit integer to the specified paramIndex. performs null handling.
  ## the return value is the sqlite returncode which 
  ## can be evaluated by the evalHasError/evalBindError template
  if val.isNone:
    result = bind_null(ps, paramIdx.int32)   
  else:
    result = bind_int64( ps, paramIdx.int32, unsafeGet(val) )


proc bindFloat64*( ps : PreparedStatement, paramIdx: int,
                   val : Option[float64]) : int {.inline.} =
  ## Binds a 64bit float to the specified paramIndex. performs null handling.
  ## the return value is the sqlite returncode which can be evaluated by 
  ## evalHasError/evalBindError template
  if val.isNone:
    result = bind_null(ps,paramIdx.int32)
  else:
    result = bind_double(ps, paramIdx.int32, unsafeGet(val))

proc bindFloat64*( ps : PreparedStatement, paramIdx: int,
                val : float64 ) : int {.inline.} =
  ## Binds a 64bit float to the specified paramIndex.
  ## This version performs no null handling and is suitable for bulk update/insert.
  ## The return value is the sqlite returncode which can be evaluated by 
  ## the evalHasError/evalBindError template
  result = bind_double(ps, paramIdx.int32, val)

proc bindNull*( ps : PreparedStatement, paramIdx: int) : int {.inline.}  =
  ## Sets the bindparam at the specified paramIndex to null 
  ## (default behaviour by sqlite).
  ## the return value is the sqlite returncode which can be evaluated by 
  ## the evalHasError/evalBindError template
  result = bind_null(ps, paramIdx.int32) 


proc bindString* ( ps      : PreparedStatement, 
                   paramIdx : int,
                   val     : var Option[string],
                   freeCb  : SQLite3UnbindCb = nil ) : int =
  ## Binds a string to the specified paramIndex. managed version with null handling.
  ## The return value is the sqlite returncode which can be evaluated by
  ## the evalHasError/evalBindError template
  if val.isNone:
    result = bind_null(ps,paramIdx.int32)
  else:
    if freeCb != nil: 
      result = bind_text(ps, paramIdx.int32, unsafeGet(val).cstring,
                       -1.int32 ,freeCb) # let look sqlite for zero-termination
    else:
      result = bind_text(ps, paramIdx.int32,unsafeGet(val).cstring,  
                       -1.int32 , SQLITE_STATIC)

proc bindString* ( ps      : PreparedStatement, 
                   paramIdx : int,
                   val     : var string,
                   freeCb  : SQLite3UnbindCb = nil ) : int =
  ## binds a string to the specified paramIndex. managed version.
  ## this version is faster than the option type but nullhandling is not performed.
  ## the return value is the sqlite returncode which can be 
  ## evaluated by the evalBindError template
  if not freeCb.isNil: 
    result = bind_text(ps, paramIdx.int32, val.cstring, 
                    -1 ,freeCb)
  else:
    result = bind_text(ps, paramIdx.int32,val.cstring, 
                    -1 , SQLITE_STATIC)
 
proc bindStringUT* ( ps     : PreparedStatement, 
                    paramIdx : int,
                    val     : pointer,
                    val_len : int32,
                 freeCb : SQLite3UnbindCb = nil ) : int  =
  ## Binds a string to the specified paramIndex. untraced version.
  ## The return value is the raw sqlite returncode which can be 
  ## evaluated by the evalBindError template
  if not freeCb.isNil: 
    result = bind_text(ps, paramIdx.int32, cast[cstring](val), val_len,freeCb)
  else:
    result = bind_text(ps, paramIdx.int32,cast[cstring](val), val_len, SQLITE_STATIC)

proc bindBlob*( ps : PreparedStatement, 
                   paramIdx : int,
                   val : var Option[seq[byte]],
                   freeCb : SQLite3UnbindCb = nil ) : int  =
  ## binds a blob to the specified paramIndex. managed version.
  ## unless this callback is executed by the backend the sequence and it's
  ## contents need to stay valid.
  ## If no callback was specified the binding method is SQLITE_STATIC.
  ## The return value is the sqlite returncode which can be evaluated by 
  ## the evalHasError/evalBindError template
  if val.isNone:
    result = bind_null(ps,paramIdx.int32)    
  else:
    var sb = unsafeGet(val)
    if not freeCb.isNil:
      result = bind_blob(ps, paramIdx.int32, unsafeAddr(sb[0]) , 
                         (sb.len).int32 ,freeCb) 
      # TODO: eval if bloblen can exceed 32 bit   
    else:
      result = bind_blob(ps, paramIdx.int32, unsafeAddr(sb[0]) , 
                         (sb.len).int32 , SQLITE_STATIC)
  
proc bindBlob*( ps : PreparedStatement, 
                 paramIdx : int,
                 val   : var seq[byte],
                 freeCb : SQLite3UnbindCb = nil ) : int  =
  ## binds a blob to the specified paramIndex. managed version.
  ## unless the callback was called by the backend the sequence needs to stay valid.
  ## if no callback was specified the binding method is SQLITE_STATIC
  ## this version is faster than the option type - nullhandling is not performed
  ## return value is the sqlite returncode which 
  ## can be evaluated by the evalHasError/evalBindError template
  if not freeCb.isNil:
    result = bind_blob(ps, paramIdx.int32, unsafeAddr(val[0]) , 
                     (val.len).int32 ,freeCb)    
                     # TODO: eval if bloblen can exceed 32 bit   
  else:
    result = bind_blob(ps, paramIdx.int32, unsafeAddr(val[0]) , 
                     (val.len).int32 , SQLITE_STATIC)
 
proc bindBlobUT* ( ps       :  PreparedStatement, 
                   paramIdx : int,
                   val      : pointer,
                   val_len  : int32,
                   freeCb   : SQLite3UnbindCb = nil ) : int  =
  ## binds a blob to the specified index. untraced version.
  ## unless the callback was called the pointer needs to stay valid.
  ## if no callback was specified the binding method is SQLITE_STATIC
  ## return value is the sqlite returncode which can be evaluated 
  ## by the evalHasError/evalBindError template
  if not freeCb.isNil:
    result = bind_blob(ps, paramIdx.int32, val, val_len ,freeCb)
  else:
    result = bind_blob(ps, paramIdx.int32, val, val_len ,SQLITE_STATIC)

type
  BulkBindToColsCb*[T] = proc(ps : PreparedStatement, 
                              bindIdx : int, 
                              bind_obj : var T) {.inline.}
  ## callback which is used by bulkBind. It´s called before step() is executed

const 
  BindIdxStart* = 1.int32
    ## defines the vendors leftmost parameter of the parameterized sql-query
  
proc bulkBind*[T](ps : PreparedStatement, 
                 binds : var openArray[T], 
                 bindCols : BulkBindToColsCb, 
                 rowParamCount : int,
                  out_msg : var RCode, 
                  paramIndex : int = BindIdxStart ) : int  = 
  ## binds a object collection to the preparedStatement. 
  ## Binding is performed on a object per row base.
  ## the number of parameters within the query must be multiple of rowParamCount because 
  ## all parameters should be bound or null values are written into the database.
  ## bulkBind returns 1 if all parameters are bound. 
  ## In case of an error the returned index points
  ## to the faulted parameter row. 
  ##
  ## If unbound params present (seq length is smaller) it returns the next paramIndex 
  ## which can be used to continue on the next call.
  ## If a error condition occurs while binding, the 
  ## returned index points to the erronous row (start parameter)
  var bindIdx = paramIndex
  let maxVals = binds.len * rowParamCount
  let paramcount = bind_parameter_count(ps)
  var maxParamsPerIter : int

  if maxVals > paramcount:
    maxParamsPerIter = paramcount
  else: 
    maxParamsPerIter = maxVals

  for obj in binds.mitems:
    if bindidx < maxParamsPerIter:
      bindCols(ps,bindIdx,obj)
      bindIdx = bindIdx + rowParamCount   
    else: # all params bound
      collectVendorRCode(out_msg):
        ps.step() 
      out_msg.collectMsgAndDoIfError(ps):
        break 
      discard ps.reset() 
      discard ps.clear_bindings()
      bindIdx = 1
      bindCols(ps,bindIdx,obj)
      bindIdx = bindIdx + rowParamCount   
 
  if bindIdx > maxParamsPerIter and not evalHasError(out_msg): # all params filled
    discard ps.step() # parameter count equal element count
    discard ps.reset()
    bindIdx = BindIdxStart

  result = bindIdx   # in case of error the index points to the faulty col 


proc newPreparedStatement*(db: DbConn, query: SqlQuery, 
                            out_ps: var PreparedStatement, 
                           out_returncode : var RCode) {.raises: [].} =
  ## returns a new compiled preparedStatement.
  ## out_returncode can be consumed the the 'eval' templates
  out_returncode.vendorcode = prepare_v2(db, query.cstring, query.string.len.cint,
                        out_ps, nil) 
  # TODO: last param returns the uncompiled part of the statement (possible better errhandling)
  out_returncode.collectMsgAndDoIfError(out_ps):
    discard

proc modifiedRowCount*(db : DbConn ) : int32 {.inline.} =
  ## reports how many rows were modified 
  ## after the last statement/step execution 
  db.changes  

proc  fetchInt64Opt*(ps : ResultSet ,cpos : int ) :  Option[int64] =
  ## fetches an integer at the given column position.
  ## in case of null option(none) is returned.  
  ## only valid if SQLITE_ROW was returned from step().
  ## the leftmost column is defined in the const ResultIdxStart
  if ps.column_type(cpos.int32) == SQLITE_NULL:
    result = none(int64)
  else:  
    result = option( ps.column_int64(cpos.int32) )

proc  fetchInt32Opt*(ps : ResultSet ,cpos : int ) :  Option[int32] =
  ## fetches an 32 bit integer at the given column position. 
  ## only valid if SQLITE_ROW was returned from step().
  ## the leftmost column starts with 0
  if ps.column_type(cpos.int32) == SQLITE_NULL:
     result = none(int32)
  else:  
    result = option( ps.column_int(cpos.int32) ) # TODO: check if this fetch 
                                                 # is compilation dependent
    
proc  fetchInt64*(ps : ResultSet, cpos : int) : int64 {.inline.} =
  ## Fast fetch an integer at the given column position(without SQLITE_NULL check).
  ## only valid if SQLITE_ROW was returned from step().
  ## If the column type does not match an internal conversion is performed - 
  ## no error delivery is performed. 
  result = (ps.column_int64(cpos.int32))

proc  fetchInt32*(ps : ResultSet, cpos : int) : int32 {.inline.} =
  ## fast fetch an integer at the given column position(without SQLITE_NULL check).
  ## Only valid if SQLITE_ROW was returned from step()
  ## if the column type does not match an internal conversion is performed
  ## no error delivery is performed. 
  result = (ps.column_int(cpos.int32)) # TODO: check if this fetch is
                                       # compilation dependent
    
proc fetchFloat64Opt*(ps : ResultSet,cpos : int) : Option[float64] =
  ## fetches a float at the given column position. managed version. null check are performed.
  if ps.column_type(cpos.int32) == SQLITE_NULL:
    result  = none(float64)
  else:
    result = option(ps.column_double(cpos.int32))

proc fetchFloat64*(ps : ResultSet,cpos : int ) : float64 {.inline.} =
  ## fast fetch a float at the given column position.
  ## if the column type does not match an internal conversion is performed 
  result = ps.column_double(cpos.int32)
    
proc fetchString*(ps :  ResultSet,
                 cpos : int, 
                  out_rc : var RCode) : Option[string] =
  ## Fetches a string at the given column position. traced version.
  ## In case of null option(none) is returned the NullValue is validated
  if ps.column_type(cpos.int32) == SQLITE_NULL:
    # probe if valid null: 
    collectVendorRCode(out_rc):
      fetchErrcode(ps)
    out_rc.collectMsgAndDoIfError(ps):
      discard    
    result = none(string)
  else:
    var rc : string 
    copyCstrToNewNimStr(rc,ps.column_text(cpos.int32))
    result = option(rc)

proc fetchString*(ps : ResultSet,cpos : int) : string {.inline.} =
  ## fast fetch a string at the given column position. traced version.
  copyCstrToNewNimStr(result,ps.column_text(cpos.int32))
  
proc fetchStringUT*(ps : ResultSet,
                    cpos : int, 
                    out_rc : var RCode) : 
                    tuple [stringptr : ptr char, len : int ] =
  ## fetches a string at the given column position. untraced version.
  ## the pointer is valid till the preparedStatement is moved to the next row.
  ## before advancing to the next row ensure that the data is copied into the
  ## application domain.
  if ps.column_type(cpos.int32) == SQLITE_NULL:
    collectVendorRCode(out_rc):
      fetchErrcode(ps) # determine if 'valid' null
    out_rc.collectMsgAndDoIfError(ps):
      discard
    result = (stringptr : nil, len : 0 )
  else: 
    let str : cstring = ps.column_text(cpos.int32)
    result = ( stringptr: str[0].unsafeAddr, len: str.len)

proc fetchBlob*(ps : ResultSet,cpos : int , out_rc : var RCode ) : Option[seq[byte]] =
  ## fetches an blob at the given column position. traced version.
  ## The blob is copied immediately into a sequence.
  ## If none is returned the errcode could be checked if dbNull wasn´t the result of an error
  ## condition
  if ps.column_type(cpos.int32) == SQLITE_NULL:
    collectVendorRCode(out_rc):
      fetchErrcode(ps) # probe if null is valid
    out_rc.collectMsgAndDoIfError(ps):
      discard
    result = none(seq[byte])
  else:
    var s : seq[byte]
    # FIXME: eval if column_blob should be called before column_bytes
    newSeq[byte](s,ps.column_bytes(cpos.int32).int) 
    copyMem(addr(s[0]), ps.column_blob(cpos.int32) ,s.len)
    result = option(s)
  
proc fetchBlobUT*(ps :  ResultSet,cpos : int ) : tuple [blobptr : pointer, len : int]  {.inline.}  =
  ## Fetches a blob at the given column position. untraced version.
  ## The pointer is valid till the preparedStatement is advanced to the next row with step()
  ## the content needs to be copied into the application domain.
  result = (ps.column_blob(cpos.int32),ps.column_bytes(cpos.int32).int)
   
type 
  PopulateCb*[T] = proc(ps : ResultSet, firstidx : int, maxcols : int, out_obj : var T) {.inline.}
  ## callback for populating a container on a resultSet row base

const 
  ResultIdxStart = 0.int32
  ## the vendors leftmost column index

proc fetchRows*[T](ps : ResultSet, out_rows : var openArray[T], fetchCols : PopulateCb[T],
                        out_msg : var RCode, rowOffset : int = 0 ) : int =
  ## Fetches multiple rows out of the PreparedStatement. How much rows are read is
  ## constrainted by the length of the given out_rows sequence. 
  ## The sequence must be preinitialized with the appropriate instances. 
  ## The integer returned indicates the number of rows iterated.
  ## rowOffset is optional and should not exceed the out_rows container length
  if not(ps.sqlite3_stmt_busy != 0):
    collectVendorRCode(out_msg):
      ps.step 
  let dcount = ps.data_count
  result = 0
  for i in countup(0,out_rows.len-1-rowOffset):
    fetchCols(ps,ResultIdxStart,dcount,out_rows[i+rowOffset])
    collectVendorRCode(out_msg):
      ps.step
    inc result
    if not out_msg.hasRows:
      out_msg.collectMsgAndDoIfError(ps):
        discard
      break

proc fetchColumnCount*( rs : var ResultSet ) : int {.inline.} =
  ## retrieves the number of columns of the ResultSet
  result = rs.data_count

proc fetchColumnNames*( ps : ResultSet , 
                        out_colnames : var seq[string] ) =
  ## Fetches the column-names of the active prepared statement 
  ## into the second parameter. 
  ## The sequence is initialized internally. 
  ## The columnnames of the result could only gathered
  ## if the preparedStatement is active. 
  ##
  ## If the preparedStatement already
  ## returned SQLITE_DONE, the result will be unspecified
  if not(ps.sqlite3_stmt_busy != 0): 
    discard ps.step

  let maxcols = ps.data_count # 0 = no_data
  newSeq(out_colnames,maxcols)

  for i in countup(0,maxcols-1):
    copyCstrToNewNimStr(out_colnames[i],column_name(ps,i.int32))

iterator allOpenPreparedStatements*(db: DbConn) : 
           PreparedStatement {.raises: [].} =
  ## iterates over all open (non-finalized) preparedStatements 
  ## for the specified connection
  var p : Pstmt = sqlite3_next_stmt(db, nil)
  while not p.isNil:
    yield p
    p = sqlite3_next_stmt(db,p)    

proc cleanupAllocatedResources*(db : DbConn, resultcode : var RCode)  =
  ## cleanup. finalizes all open prepared Statements for the specified
  ## connection. 
  for p in allOpenPreparedStatements(db):
    if p.sqlite3_stmt_busy != 0: # statement stepped at least once
      discard p.reset
    collectVendorRCode(resultcode):
       p.sqlite3_finalize
    resultcode.collectMsgAndDoIfError(db):
      discard

proc exec*(db: DbConn, query: SqlQuery, rc : var RCode )   = 
  ## Suitable for execution of commands which do not return any results 
  ## or executed only once.
  ## If an error happens the backend returns with an error message.
  ## in this case the errStr field of the returncode is set.
  var errmsg_int : cstring  
  # TODO: evaluate - there is a difference between cast[cstring](str) 
  # and str.cstring
  rc.vendorcode = exec(db,query.cstring,nil,nil,errmsg_int).int
  if not errmsg_int.isNil:
    copyCstrToNewNimStr(rc.errStr,errmsg_int)
    nimdb_sqlite3w.free(errmsg_int)
  
const
  RawstrLengthSize = 2 # we occupy a word to store the stringlength
  
# naive raw buffer backend handling.  
# limitations: no pool, no threadsafe access, only variable-length-datatype(string)
# supported. no compression. TODO: move2common, generic resultval handling and varchar compression
template rawBufferToStringSeq(ptr2buffer : pointer, cols: int, container : var seq[seq[string]])  =
  ## internal template to access the raw buffer and convert the
  ## storage part to a sequence with sequences(per row). used by the extended exec interface
  let bh : ptr BuffHdr = cast[ptr BuffHdr](ptr2buffer)      
  var totalElemCount : int = bh.element_count 
  var rowCount : int =  ( totalElemCount / cols ).int
 
  if container.len < rowCount:
    # grab the smaller value: maxRowcount or seq-length
    rowCount = container.len

  var eptr : ptr int16 = cast[ptr int16]( (cast[int](ptr2buffer))+(sizeof(BuffHdr)) )
  # start of strlist
  var strlen : int16
  var ptr2content : pointer

  for r in countup(0,rowCount-1):
    var c : seq[string] = container[r] 
    var columns : int = cols
    # if the columncount of the resultset is higher than the sequence length
    # truncate the results (skip cols)     
    for cidx in countup(0,columns-1): 
      strlen = eptr[]
      if cidx < c.len: # skip columns which does not fit in
        var nstr : string = newString(strlen)
        if strlen > 0:
          ptr2content = cast[pointer](cast[int](eptr) + RawstrLengthSize )
          copyMem(addr(nstr[0]),ptr2content,strlen)   
        else:
          nstr = ""
        c[cidx] = nstr  # TODO avoid copying strings here (twice) 
      eptr = cast[ptr int16]( (cast[int](eptr))+strlen + RawstrLengthSize )
    container[r] = c # TODO: eval if the seq is copied here
     
type 
  BuffHdr = tuple[ element_count : int, 
                   p_buffend : ptr byte, 
                   bytes_used : int]
  
template addCstrToBuffer(ptr2buffer : pointer, cstr : var cstring) = 
  ## internal template to access the raw buffer
  ## adds a cstr to the buffer. used by the extended exec interface
  let slen : int = cstr.len
  
  if slen < int16.high: 
    # only process further if the strlen does not exceed the length-field (2bytes)
    # alternative: always insert but truncate it
    let strlen : int16 = slen.int16
    let bh : ptr BuffHdr = cast[ptr BuffHdr](ptr2buffer) # map header    
    let bytecount : int =  bh.bytes_used   
    let ptr2freeSlot : ptr byte = cast[ptr byte](cast[int](ptr2buffer) + bytecount)

    if cast[int](bh.p_buffend) > (cast[int](ptr2freeSlot) + strlen + RawstrLengthSize ):    
      # only process further if we have free buffer space
      var eptr : ptr int16 = cast[ptr int16](ptr2freeSlot)
      eptr[] = strlen.int16 # set strlength
      
      if strlen > 0:
        copyMem(cast[ptr byte](cast[int](ptr2freeSlot) + RawstrLengthSize ),cstr,strlen)
      
      inc bh.element_count
      bh.bytes_used = bytecount + (strlen + RawstrLengthSize )

type
  CbResult = tuple[ in_seqlength:int,
                       out_colcount:int,
                       out_rowsread: int ,
                       in_memptr: pointer, 
                       in_memsize_b:int ]
  # needed for handshaking between backend-cb (unknown context) and proc

proc execCallback(context : pointer, 
                  numcols : int32, 
                  fields, colnames : cstringArray) : int32 {.cdecl.} =
  # we do not know in which thread-context we are running here. 
  # due to that we copy the results into a custom
  # shared mem block
  result = 0 # return 0 for indicating: ok, next row
  var hsc : ptr CbResult = 
          cast[ptr CbResult ](context)
  let bufferptr : ptr int = cast[ptr int](hsc[].in_memptr)

  let memsizeBytes : int = hsc[].in_memsize_b

  let bh : ptr BuffHdr = cast[ptr BuffHdr](bufferptr)
  
  if hsc[].out_colcount == 0:
    # init, first call of cb
    hsc[].out_colcount = numcols.int
    hsc[].out_rowsread = 0
    bh.p_buffend =   cast[ptr byte]((cast[int](bufferptr)+memsizeBytes))
    bh.bytes_used = sizeof(BuffHdr)
    bh.element_count  = 0
    # read colnames first
    for i in countup(0,numcols-1):
      addCstrToBuffer(bufferptr,colnames[i])
    hsc[].out_rowsread = 1
      
  # calc avg freespace
  let avgrowlen : int = ( bh.bytes_used / (hsc[].out_rowsread+1)).int
  let freerowcount : int =  (memsizeBytes / avgrowlen).int
 
  if freerowcount > 3:
    # hopefully enough space for next row       
    for i in countup(0,numcols-1):
      addCstrToBuffer(bufferptr,fields[i])
    inc hsc[].out_rowsread  
  else:
    result = 1 # bail out

  result = 0 # if non zero is returned, callback not invoked again


proc exec*(db: DbConn, query: SqlQuery,  out_rc : var RCode,
           out_results : var seq[seq[string]], 
           buffer : pointer, buffsize : int )  = 
  ##          
  ## suitable for execution of commands which do not return any or much results.  
  ##
  ## if an error happens the backends message is filled into out_rc.errstr.
  ## in case of success out_rc.errstr is empty.
  ##
  ## if out_results is initialized, the sequence will be filled with the returned rows
  ## till the given shared buffer's limit is reached.
  ##
  ## always initialize outer and nested seqs.
  ## first row is always filled with the returned columnNames; 
  ##
  ## to avoid reading huge sets, preset the sequence with the number of expected/needed elements.
  ## the internal header occupies 4 integer; each returned string occupies an 
  ## extra 32bit-word for the lengthfield.
  ## 
 
  
  if out_results is type(nil): 
    exec(db,query,out_rc) # exec without callback
  else:
    if buffsize <= sizeof(BuffHdr):
      out_rc.collectVendorRCode:
        SQLITE_ERROR
      out_rc.errStr = "ndbc - Abort: buffsize too small. "
      return 

    let callbackResult : CbResult  = 
                              (in_seqlength: out_results.len,
                               out_colcount: 0,
                               out_rowsread: 0, 
                               in_memptr : buffer, 
                               in_memsize_b : buffsize)
    
    let cbrptr : ptr CbResult = unsafeAddr(callbackResult)
    
    # shared memory was allocated and the callback populates it till 
    # end of block reached or all rows consumed
    var errmsg_int : cstring  
    
    collectVendorRCode(out_rc):    
      exec(db,query.cstring,execCallback,cast[pointer](cbrptr),errmsg_int) # wrapper call
  
    if not errmsg_int.isNil:
      copyCstrToNewNimStr(out_rc.errStr,errmsg_int)
      nimdb_sqlite3w.free(errmsg_int)

    if cbrptr.out_rowsread > 0:
      # copy contents but only if results present
      rawBufferToStringSeq(cbrptr.in_memptr,cbrptr.out_colcount,out_results)


proc exec*(db: DbConn, query: SqlQuery, rc : var RCode, 
           out_results : var seq[seq[string]], 
           buffsize : int = 1024 )  = 
  ## convenience proc. allocates shared memory for given buffsize   
  let buffer = allocShared0(buffsize)
  exec(db,query,rc,out_results,buffer,buffsize)
  deallocShared( buffer )

proc queryOneRow*(db : DbConn,query:SqlQuery,rc: var Rcode, numCols : int) : seq[string] =
  ## convenience proc which returns only the first row of the query 
  ## without the column names. if numCols is smaller than the returned number of
  ## columns (ResultSet) the row is truncated
  var seqcontainer : seq[seq[string]]
  newSeq(seqcontainer,2)
  newSeq(seqcontainer[0],numCols)
  newSeq(seqcontainer[1],numCols) 
  exec(db,query,rc,seqcontainer)
  result = seqcontainer[1]

template withTransaction*( dbconn : DbConn, rc : var RCode, body: untyped) =
  ## used to encapsulate the operation within a transaction.
  ## rollback is performed by a technical fault condition, if an exception
  ## is thrown or if the RCode container was tagged with forceRollback()
  ## 
  ## this template is not nestable if the vendor does not support it

  bind collectMsgAndDoIfErrorElse
  block:
    dbconn.exec(sql"BEGIN;",rc)
    try:
      body
    except:
      dbconn.exec(sql"ROLLBACK;",rc)
      raise
    collectMsgAndDoIfErrorElse(rc,dbconn) do:
      var ec : RCode 
      dbconn.exec(sql"ROLLBACK;",ec) # hacky; prevent overwrite previous err
    do:     # else
      dbconn.exec(sql"COMMIT;",rc)


template withFinalisePreparedStatement*(ps : PreparedStatement, 
                                        rcode : var RCode,
                                        body: untyped ) =
  ## finalizes the preparedStatement after leaving the block.
  ## it can't be used later on.
  # TODO: error handling
  bind finalize
  body  
  collectVendorRCode(rcode):
    finalize(ps)  
  rcode.collectMsgAndDoIfError(ps):
    discard

template rawBind*( ps : PreparedStatement,
                     out_rc : var RCode, 
                       body : untyped) : untyped {.dirty.} =
  ## template for raw-binding used within a custom loop.
  ## null type fetching must be handled manually. suitable for insert/update/upsert
  ## statements
  ## The variable "baseIdx" inside template's scope 
  ## starts with the vendors defined leftmost index. It needs to be advanced to the next
  ## parameter if an iteration is inside the template´s scope (multiple parameters present) 
  ## (see speed_comparison.nim for an example)
  bind collectVendorRCode
  bind collectMsgAndDoIfError
  # bind PreparedStatement
  bind step
  bind reset
  block: # needed for template nesting
    var baseIdx : int32 = BindIdxStart
    body
    collectVendorRCode(out_rc):
      step(ps)     # execute query
    out_rc.collectMsgAndDoIfError(ps):
     discard
    discard ps.reset    # reset state machine

template rawFetch*( ps : ResultSet , out_rc : var RCode, body : untyped )  {.dirty.} =
  ## template for raw fetching results used within a custom loop.
  ## always call 'getResultSet' before using this template.
  ## the variable colIdx inside the template's scope
  ## starts with the vendors defined leftmost index.
  bind ResultIdxStart, collectVendorRCode
  bind collectMsgAndDoIfError
  bind SQLITE_OK
  bind step
  block: # needed for template nesting
    var colIdx : int32 = ResultIdxStart
    collectVendorRCode(out_rc):
      SQLITE_OK
    body
    collectVendorRCode(out_rc):
      step(ps) #  advance to the next row if present
    out_rc.collectMsgAndDoIfError(ps):
      discard

template withRollbackTransaction*(dbconn : DbConn, rc : var RCode, body : untyped) =
  ## performs always a rollback, regardless if error or not. suitable for testing purposes.
  var rc_int : int # TODO: eval returncode
  dbconn.exec(sql"BEGIN;",rc)
  try:
    body 
  except:
    dbconn.exec(sql"ROLLBACK;",rc)
    raise
  finally:
    dbconn.exec(sql"ROLLBACK;",rc)

template withNestedTransaction*( dbconn : DbConn, rc : var RCode, 
                                 transactionName : string, body: untyped) =
  ## use this template if you need nestable statement encapsulation.
  ## transactionName's should be unique within the transaction-tree.
  ## further reading: 
  ## * https://www.sqlite.org/lang_transaction.html
  ## * https://www.sqlite.org/atomiccommit.html
  block:
    conn.exec sql"SAVEPOINT " & transactionName,rc
    try:
      body
    except:
      dc.exec sql"ROLLBACK TO " & transactionName,rc
      raise
    if evalHasError(rc):
      var ec : RCode 
      dc.exec(sql"ROLLBACK TO " & transactionName,ec) # hacky. prevent overwrite previous err  
    else:
      dc.exec sql"RELEASE " & transactionName,rc

iterator validateSql*( dbconn : DbConn, queries: openArray[SqlQuery], rc: var RCode ) : string =
  ## experimental iterator which validates each sql. each query is wrapped into
  ## a transaction before execution and a rollback is performed after.
  ## each error is yielded. the intention is to detect syntax errors.
  ## keep in mind that at least one vendor does not support 
  ## transactional ddl and performs a 
  ## forced commit if a ddl is executed. 
  ## resultcode SQLITE_CONSTRAINT: not null constraint  is suppressed
  for i in countup(0,queries.len-1):
    let sqlq = queries[i]
    if sqlq is not type(nil):
      withRollbackTransaction(dbconn,rc):
        dbconn.exec(sqlq,rc)
        rc.collectMsgAndDoIfError(dbconn):
          if rc.vendorcode != SQLITE_CONSTRAINT: # was not parsed
            yield  " [" & cast[string](queries[i]) & "] ==> " & $rc 

proc incarnateDbFromTemplate*(targetDb: DbConn, absPathWithFilename : string, out_rc : RCode ) =
  ## vendor specific helper to incarnate a targetDb from a source database file (template).
  ## the source database is opened in readonly mode and copied into the
  ## targetDb connection. Databasename 'main' is assumed. keep in mind that the
  ## targetDbs connection is not allowed to have any pending transactions open.
  ## out_rc is the returncode.
  var out_rc : RCode
  var ext_ec : int # extended errorcode
  let srcdb = open(absPathWithFilename,"","",out_rc,ext_ec,SQLITE_OPEN_READONLY)
  if not out_rc.evalHasError:   
    dumpDbTo(srcdb,targetDb,out_rc)
  srcdb.close(out_rc)  

type 
  SQLite3ColumnMetaData* = object of DbTableColumnMetaData
    tableName* : string
    columnName* : string
    declDataType* : string
    ## decleared data type (note: sqlite stores the data typeless)
    collationSeqName* : string 
    ## how things are sorted
    notNull* : bool
    ## true if column is defined as not null
    partOfPK* : bool
    ## true if column is part of a pk
    autoInc* : bool
    ## true if autoincremented

proc `$`*(p : DbTableColumnMetaData): string =
  ## debugging purpose
  let par = cast[SQLite3ColumnMetaData](p)
  result = "TableName: " & par.tableName & "\n" & 
           "ColName: " & par.columnName & "\n" &
           "decl. Datatype: " & par.declDataType & "\n" &
           "collationSeqName : " & par.collationSeqName & "\n" &
           "notnull = " & $par.notNull & 
           "/ partOfPk = " & $par.partOfPK & 
           "/ autoInc = " & $par.autoInc

proc tableColumnMetadata*(dbConn : DbConn, 
                           tableName : string, 
                          columnName : string, 
                              out_rc : var RCode , 
                              dbName : string = "main" ) : 
                              SQLite3ColumnMetaData =
  ## returns metadata for a specified column and table. 
  ## the dbName could be present or nil
  var out_decldatatype : cstring
  var out_collseqname : cstring
  var out_notnull : int
  var out_partOfPk : int
  var out_autoinc : int

  collectVendorRCode(out_rc):
    sqlite3_table_column_metadata(dbConn,
                                             dbName.cstring,
                                             tableName.cstring,
                                             columnName.cstring,
                                             out_decldatatype,
                                             out_collseqname,
                                             out_notnull,
                                             out_partOfPk,
                                             out_autoinc)
    
  if not evalHasError(out_rc):
    result.tableName = tableName
    result.columnName = columnName
    var decltype : string
    var cseqname : string
    copyCstrToNewNimStr(decltype,out_decldatatype)

    block b1: # workaround due to template used twice within scope
      copyCstrToNewNimStr(cseqname,out_collseqname)

    result.declDataType = decltype
    result.collationSeqName = cseqname
    result.notNull = out_notnull != 0
    result.partOfPK = out_partOfPk != 0
    result.autoInc = out_autoinc != 0
  else:
    out_rc.errStr = $errmsg(dbConn)  

proc columnNamesForTable*(dbConn : DbConn, 
                         tableName: string, rc : var RCode) : seq[string] =
  var ps : ResultSet
  let query = "select * from pragma_table_info('" & tableName & "');"
  newPreparedStatement(dbConn,sql(query),ps,rc)
  if not rc.evalHasError:
    withFinalisePreparedStatement(ps,rc):
      let rs = getResultSet(ps,rc)
      result.setlen(0)
      while hasRows(rc):
        rawFetch(rs,rc):
          result.add( rs.fetchString(colIdx + 1) ) 
          # could change on each SQLITE3 version
  
proc allUserTableNames*(dbConn: DbConn, rc : var RCode, 
                          dbName : string = "main") : seq[string]=
  ## helper to retrieve all db-object table types from specified db
  let query = "select name from " & dbName & ".sqlite_master " &
              " where type = 'table' and name not like ('sqlite_%'); "
  var ps : PreparedStatement
  newPreparedStatement(dbConn,sql(query),ps,rc)
  if not rc.evalHasError:
    withFinalisePreparedStatement(ps,rc):
      let rs = getResultSet(ps,rc)
      while hasRows(rc):
        rawFetch(rs,rc):
          result.add( rs.fetchString(colIdx) )

proc allUserIndexNames*(dbConn : DbConn, rc : var RCode, 
                        dbName : string = "main") : seq[string] =
  ## fetches all dbobjects of type : index
  let query = "select name from " & dbName & ".sqlite_master " &
              " where type = 'index' and name not like ('sqlite_%'); "
  var ps : PreparedStatement
  newPreparedStatement(dbConn,sql(query),ps,rc)
  if not rc.evalHasError:
    withFinalisePreparedStatement(ps,rc):
      let rs = getResultSet(ps,rc)
      while hasRows(rc):
        rawFetch(rs,rc):
          result.add( rs.fetchString(colIdx) )

proc allUserViewNames*(dbConn : DbConn, rc : var RCode, 
                                  dbName : string = "main") : seq[string] =
  ## fetches all dbobjects of type : view
  ## fetches all dbobjects of type : index
  let query = "select name from " & dbName & ".sqlite_master " &
              " where type = 'view' and name not like ('sqlite_%'); "
  var ps : PreparedStatement
  newPreparedStatement(dbConn,sql(query),ps,rc)
  if not rc.evalHasError:
    withFinalisePreparedStatement(ps,rc):
      let rs = getResultSet(ps,rc)
      while hasRows(rc):
        rawFetch(rs,rc):
          result.add( rs.fetchString(colIdx) )

proc metadataForTable*(dbConn : DbConn , 
                       tableName : string, rc : var RCode,
                       dbName : string = "main") :
                      seq[SQLite3ColumnMetaData] =
  ## returns the metadata for specified table
  let colnames = columnNamesForTable(dbConn,tableName,rc)
  newSeq(result,colnames.len)
  for i in countup(0,colnames.len-1):
    result[i] = tableColumnMetadata(dbConn,tableName,colnames[i],rc,dbName)

# TODO: more examples : shared inmemory db (sharedCache on)
#           shared file
#           locking examples (possible deadlock resolving?)
# TODO:
# retrieve identity back from insert stmt if caller needs that (probe for parallel safety)
# sqlite_busy_handler/ unlock notify api https://www.sqlite.org/unlock_notify.html
# incremental blob api
# WAL (concurrency)
# programmatic cacheflush
# sqlite3_create_collation() u. collation
# int sqlite3_vtab_config(sqlite3*, int op, ...);
# configure db-connections with sqlite3_db_config
# sqlite_trace_v2 interface
# utilize system tables: sqlite_master, sqlite_tmp_master, sqlite_sequence
# custom window functions https://www.sqlite.org/c3ref/create_function.html
# sqlitel.org/src/doc/trunc/ext/user_auth
# custom udf-code into sqlite3 : https://www.sqlite.org/loadext.html
# database query facility / preparedstatements / UDF
# sql cipher support https://www.zetetic.net/sqlcipher