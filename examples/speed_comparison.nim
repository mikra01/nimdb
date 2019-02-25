# comparison of the classic db_sqlite and nimdb
# we setup the in memory database from template 
import times
import db_sqlite
include setup_example_env

# perform classic insert
echo "classic insert with db_sqlite: 1 million rows into main.testtable "
var dbc : db_sqlite.DbConn = cast[db_sqlite.DbConn](db)
var t2 = cpuTime()
  
dbc.exec(sql"BEGIN")
for i in 1..1000000: # insert 1m testrows
  let str = "... this is a long teststring ... " & $i
  dbc.exec(sql"insert into main.testtable (testcol1,testcol2) values ( ?,? ) ",
                              str,i.toFloat)
dbc.exec(sql"COMMIT ")
 
echo "time elapsed 1mio records inserted (classic): " & $(cpuTime()-t2)

# perform now bulk insert with nimdb

echo "insert with nimdb_sqlite: another 1 million rows into main.testtable.. "

t2 = cpuTime()
var ps: PreparedStatement  
newPreparedStatement(db,sql"""insert into main.testtable (testcol1,testcol2) values 
                               (?,?),(?,?),(?,?),(?,?),(?,?),
                               (?,?),(?,?),(?,?),(?,?),(?,?);
                                  """, ps , returncode )
# example bulk insert 1mio rows
withTransaction(db, returncode):  
  withPreparedStatement(ps,returncode):
    for i in 1..100000:
      rawBind(ps,returncode): # bulk bind with 10 row inserts at once
        for x in 0..9:
          var str = "... this is a long teststring ... " & $i
          discard ps.bindString(baseIdx,str)
          discard ps.bindFloat64(baseIdx+1,(i+x).toFloat)
          baseIdx = baseIdx + 2    
  assert(evalHasError(returncode) == false,$returncode)


echo "time elapsed 1mio records inserted with nimdbc (rawBind) " & $(cpuTime()-t2)

# reading now 2million rows..

# get the colcount
let firstRow = db.queryOneRow(sql"select count(*) as colcount from main.testtable; ",returncode,1)

echo "classic read of " & firstRow[0] & " rows.."

let cr_t1 = cpuTime()

var cr_rowsfetched  = 0

for x in dbc.fastRows(sql"select id,testcol1,testcol2 from main.testtable; "):
  inc cr_rowsfetched 

echo "runtime classic read fetch: " & $(cpuTime() - cr_t1)
echo "total rows fetched : " & $cr_rowsfetched

# raw fetch 2million rows

var pk : int64
var str : string
var val : float64

newPreparedStatement(db,sql"select id,testcol1,testcol2 from main.testtable; ",ps,returncode)

let tr = cpuTime()

cr_rowsfetched = 0

withPreparedStatement(ps,returncode):
  let r = getResultSet(ps,returncode)
  while hasRows(returncode):
    rawFetch(r,returncode):
      pk = r.fetchInt64(colIdx)
      str = r.fetchString(colIdx+1)
      val = r.fetchFloat64(colIdx+2)
    inc cr_rowsfetched

assert(evalHasError(returncode) == false,$returncode)
      
echo "runtime raw fetch: " & $(cpuTime() - tr)
echo "total rows fetched : " & $cr_rowsfetched


    