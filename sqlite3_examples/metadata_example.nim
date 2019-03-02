# example usage of the metadata api
# dynamic table clone example
# 
# all tables from the testdb are cloned.

import options,strutils,sequtils

include setup_example_env


# inject 1 million rows into testtable
var ps : PreparedStatement  
newPreparedStatement(db,sql""" insert into main.testtable (testcol1,testcol2) values 
                       (?,?),(?,?),(?,?),(?,?),(?,?),
                       (?,?),(?,?),(?,?),(?,?),(?,?); """, ps,returncode) 
                       # bulk insert 10 rows at once

echo "inserting testdata : 1.000.000 rows : "
withFinalisePreparedStatement(ps,returncode):  
# after leaving this block the preparedStatement will be finalized                                     
  withTransaction(db, returncode):
    # after this block transaction ends (commit)
    for i in countup(1,100000):
      rawBind(ps,returncode): # bulk bind with 10 row inserts at once with parameters
        for x in countup(1,10):
          var str = "teststring" & $(x+i)
          discard ps.bindString(baseIdx,str)
          discard ps.bindFloat64(baseIdx+1,(i+x).toFloat)
          baseIdx = baseIdx + 2 
    if returncode.evalHasError:
      echo $returncode

proc seq2string( stringseq : var seq[string ]) : string =
    for x in stringseq:
        result = result & x

proc insertCols(out_result: var seq[string], cols : var seq[string]) =         
  for colpart in cols:
    out_result.add(colpart)
    out_result.add(",")
  out_result.setLen(out_result.len-1) # strip ',' away

proc doTableClone(db : nimdb_sqlite3.DbConn,
                  srctabname : string, 
                  clonetabname : string, 
                  rc : var RCode)  =
    let colmetadata = metadataForTable(db,srctabname,rc)
    var insertCols : seq[string] = @[]
    var selectCols : seq[string] = @[]
    var createCols : seq[string] = @[]
 
    for cm in colmetadata:
        createCols.add(cm.columnName & " " & cm.declDataType)
        if not cm.autoInc:
            insertCols.add(cm.columnName)
            selectCols.add(cm.columnName)
    var createstmt : seq[string] = @[]
    var stmtpart = "CREATE TABLE main." & clonetabname & " ( "
    createstmt.add( stmtpart )
    createstmt.insertCols(createCols)
    createstmt.add(" );")    

    var insertstmt : seq[string] = @[]
    var insertpart = "INSERT INTO main." & clonetabname & " ( "
    insertstmt.add(insertpart)
    insertstmt.insertCols(insertcols)
    insertstmt.add(")")
 
    var selectstmt : seq[string] = @[]
    selectstmt.add(" SELECT ") 
    selectstmt.insertCols(selectcols)
    selectstmt.add(" FROM main.")
    selectstmt.add(srctabname)
    selectstmt.add(";") 
 
    var insertfromselect = concat(insertstmt,selectstmt)
    
    db.exec(SqlQuery(seq2string(createstmt)),rc)
    if not rc.evalHasError:
      db.exec(SqlQuery(seq2string(insertfromselect)),rc)
      # per default we are running in autocommit mode


let tablenames = allUserTableNames(db,returncode)

for tn in tablenames: # browse tablenames
    var clonename = tn & "_clone"
    doTableClone(db,tn,clonename,returncode) 
    if not returncode.evalHasError:
      echo "table " & tn & " cloned into " & clonename
    else:
      echo $returncode 

let tablenamesAfterClone = allUserTableNames(db,returncode)
echo $tablenamesAfterClone

let cols = db.queryOneRow(sql"select count(*) from main.testtable_clone;",returncode,1)
echo "rows processed : " & cols[0]

db.close(returncode)