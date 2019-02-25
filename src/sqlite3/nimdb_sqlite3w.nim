# the sqlite3 wrapper
# we prefixed the dll calls with sqlite3_ to avoid name clashes
# and to quickref the corresponding c function
# some calls are used from the classic sqlite3 wrapper

## extends nim's sqlite3 wrapper with more API calls wrapped.
## further reading: 
## * https://www.sqlite.org/c3ref/intro.html

include sqlite3 # read classic sqlite3 wrapper
# the proc name should be equals to the foreign libraries name 
# (easier to read the vendors documentation)
proc sqlite3_finalize*(pStmt: Pstmt): int32{.cdecl, dynlib: Lib,
                                     importc: "sqlite3_finalize".}
  ## finalizes the prepared statement - mandatory to prevent memory leaks

proc sqlite3_step*(pStmt: Pstmt): int32{.cdecl, dynlib: Lib,
                                     importc: "sqlite3_step".}
  ## finalizes the prepared statement - mandatory to prevent memory leaks  

proc sqlite3_db_handle*(para1: Pstmt): PSqlite3 {.cdecl, 
  dynlib: Lib, importc: "sqlite3_db_handle".}
  ## fetches the connection the prepared statement is bound to

proc sqlite3_stmt_busy*(pstmt : Pstmt ) : int32 {.cdecl, dynlib: Lib,importc: "sqlite3_stmt_busy".}

proc sqlite3_next_stmt*(dbcon : PSqlite3, prepStmt : Pstmt) : Pstmt{.cdecl, 
  dynlib: Lib, importc: "sqlite3_next_stmt".}
  ## fetches the next preparedStatement of the specified connection
  ## - if the given pStmt is null the first one is returned. if null is returned
  ## no more prepared_statements are present

proc sqlite3_sql*(prepStmt : Pstmt ) : cstring{.cdecl, 
  dynlib: Lib, importc: "sqlite3_sql".}
  ## The sqlite3_sql(P) interface returns a pointer to a copy 
  ## of the UTF-8 SQL text used to create prepared statement P 

proc sqlite3_normalized_sql*(prepStmt : Pstmt ) : cstring{.cdecl, 
dynlib: Lib, importc: "sqlite3_sql".}
  ## The sqlite3_normalized_sql(P) interface returns a pointer to a copy 
  ## of the UTF-8 SQL text used to create prepared statement P 

# online backup api
# regarding the online backup_api please take a look at
# www.sqlite.org/backup.html
type
  Sqlite3Backup* {.pure , final .} = object 
  PSqlite3Backup* = ptr Sqlite3Backup

proc sqlite3_backup_init*( destDb :  PSqlite3, destDbName : cstring,
                          srcDb : PSqlite3, srcDbName : cstring) :  PSqlite3Backup{.
                importc: "sqlite3_backup_init", cdecl, dynlib: Lib.}
proc sqlite3_backup_step*(p : pointer, nPage : int) : int{.
                importc: "sqlite3_backup_step", cdecl, dynlib: Lib.}
proc sqlite3_backup_remaining*(p : var PSqlite3Backup) : int {.
                importc: "sqlite3_backup_remaining", cdecl, dynlib: Lib.}
proc sqlite3_backup_pagecount*(p : var PSqlite3Backup) : int {.
                importc: "sqlite3_backup_pagecount", cdecl, dynlib: Lib.}
proc sqlite3_backup_finish*(p : pointer) : int {.
                importc: "sqlite3_backup_finish", cdecl, dynlib: Lib.}

# end online backup api

proc sqlite3_extended_result_codes* : int {.
                importc: "sqlite3_extended_result_codes", cdecl, dynlib: Lib.}
proc sqlite3_extended_errcode*: int {.
                importc: "sqlite3_extended_errcode", cdecl, dynlib: Lib.}

# sqlite3_open_v2_api

# open_v2 consts
# TODO: 2enum
const 
  SQLITE_OPEN_READONLY* =        0x00000001.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_READWRITE* =       0x00000002.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_CREATE* =          0x00000004.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_DELETEONCLOSE* =   0x00000008.int    #/* VFS only */
  SQLITE_OPEN_EXCLUSIVE* =       0x00000010.int    #/* VFS only */
  SQLITE_OPEN_AUTOPROXY* =       0x00000020.int    #/* VFS only */
  SQLITE_OPEN_URI* =             0x00000040.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_MEMORY* =          0x00000080.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_MAIN_DB* =         0x00000100.int    #/* VFS only */
  SQLITE_OPEN_TEMP_DB* =         0x00000200.int    #/* VFS only */
  SQLITE_OPEN_TRANSIENT_DB* =    0x00000400.int    #/* VFS only */
  SQLITE_OPEN_MAIN_JOURNAL* =    0x00000800.int    #/* VFS only */
  SQLITE_OPEN_TEMP_JOURNAL* =    0x00001000.int    #/* VFS only */
  SQLITE_OPEN_SUBJOURNAL* =      0x00002000.int    #/* VFS only */
  SQLITE_OPEN_MASTER_JOURNAL* =  0x00004000.int    #/* VFS only */
  SQLITE_OPEN_NOMUTEX* =         0x00008000.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_FULLMUTEX* =       0x00010000.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_SHAREDCACHE* =     0x00020000.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_PRIVATECACHE* =    0x00040000.int  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_WAL* =             0x00080000.int    #/* VFS only */

# type  # boolean operators for combining flags seem not to work with enum actually
#  SqliteOpenV2Flags* = enum OPEN_READONLY =     0x00000001.int,  
#                            OPEN_READWRITE =    0x00000002,
#                            OPEN_CREATE =       0x00000004,
#                            OPEN_URI =          0x00000040,
#                            OPEN_MEMORY =       0x00000080,
#                            OPEN_NOMUTEX =      0x00008000,
#                            OPEN_FULLMUTEX =    0x00010000,
#                            OPEN_SHAREDCACHE =  0x00020000,
#                            OPEN_PRIVATECACHE = 0x00040000

proc sqlite3_open_v2*(filename: cstring, pDb : var PSqlite3, 
                      flags : int , zVfsName : cstring ) : int32{.
                        cdecl,dynlib: Lib,importc: "sqlite3_open_v2".}

proc sqlite3_db_readonly*(ppDb : var PSqlite3, dbname : cstring) : int32{.
                        cdecl,dynlib: Lib,importc: "sqlite3_db_readonly".}
  ## returns 1 if the specified db is in readonly mode

# sqlite3 incremental blob api
# todo: wrap
type
  Sqlite3IncrBlob* {.pure , final .} = object 
  PSqlite3IncrBlob* = ptr Sqlite3IncrBlob


# end of blob api

# end sqlite3_open_v2_api

# sqlite3_misc
proc sqlite3_malloc*(ppDb : PSqlite3, dbname : cstring) : int32{.
                        cdecl,dynlib: Lib,importc: "sqlite3_db_readonly".}
##
proc sqlite3_free*(ppDb : PSqlite3, dbname : cstring) : int32{.
                        cdecl,dynlib: Lib,importc: "sqlite3_db_readonly".}
##
proc sqlite3_set_last_insert_rowid*(para1: PSqlite3, val:int64) {.cdecl, dynlib: Lib,
    importc: "sqlite3_set_last_insert_rowid".} 
proc sqlite3_db_cacheflush*(para1: PSqlite3) : int32 {.cdecl, dynlib: Lib,
    importc: "sqlite3_db_cacheflush".}

proc sqlite3_system_errno*(para1:PSqlite3) : int {.cdecl, dynlib: Lib,
    importc: "sqlite3_system_errno".}

# TODO: utilize
proc sqlite3_stmt_status(ps : Pstmt, op : int, resetFlag : int) : int {.cdecl, dynlib: Lib,
    importc: "sqlite3_stmt_status".}
# TODO: utilize
proc sqlite3_db_status(db : PSqlite3, op,pcur,phiwtr,resetFlag : int) : int {.cdecl, dynlib: Lib,
    importc: "sqlite3_db_status".}

proc sqlite3_table_column_metadata*(db : PSqlite3, 
                                   dbname : cstring, # dbname or null
                                   tableName : cstring, # tablename
                                   columnName: cstring, # columnname
                                   out_decltype : var cstring, # output decl datatype
                                   out_collseqname : var cstring, # collation_sequence_name
                                   out_notNull : var int, # true if not null constraint
                                   out_primaryKey : var int, # true if column part of pk
                                   out_autoInc : var int) : int{.cdecl, dynlib: Lib,
    importc: "sqlite3_table_column_metadata".}


proc sqlite3_expanded_sql( ps : Pstmt , sqlstr : var cstring) {.cdecl, dynlib: Lib,
    importc: "sqlite3_expanded_sql".}
    # handy to check if all params are bound
    # the returned string must be freed with: sqlite3_free

# end of sqlite3_misc

