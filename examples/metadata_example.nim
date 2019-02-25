# example usage of the metadata api
# we dynamically clone all tables

import options,strutils,sequtils

include bulk_bind

let tablenames = allUserTableNames(db,returncode)

# todo insert rows here

proc seq2string( stringseq : var seq[string ]) : string =
    for x in stringseq:
        result = result & x

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
    for colpart in createCols:
        createstmt.add(colpart)
        createstmt.add(",")
    createstmt.setLen(createstmt.len-1)
    createstmt.add(" );")    
    var insertstmt : seq[string] = @[]
    var insertpart = "INSERT INTO main." & clonetabname & " ( "
    insertstmt.add(insertpart)
    for colpart in insertcols:
        insertstmt.add(colpart)
        insertstmt.add(",")      
    insertstmt.setLen(insertstmt.len-1)
    insertstmt.add(")")
    var selectstmt : seq[string] = @[]
    selectstmt.add(" SELECT ") 
    for colpart in selectcols:
        selectstmt.add(colpart)
        selectstmt.add(",")
    selectstmt.setLen(selectstmt.len-1)
    selectstmt.add(" FROM main.")
    selectstmt.add(srctabname)
    selectstmt.add(";") 
    var insertfromselect = concat(insertstmt,selectstmt)
   
    db.exec(SqlQuery(seq2string(createstmt)),rc)
    if not rc.evalHasError:
      db.exec(SqlQuery(seq2string(insertfromselect)),rc)
    else:
      echo $rc     

for tn in tablenames: # browse tablenames
    var clonename = tn & "_clone"
    doTableClone(db,tn,clonename,returncode) 
    if not returncode.evalHasError:
        echo "table " & tn & " cloned into " & clonename

db.close(returncode)