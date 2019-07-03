# artificial foreign key example with 
# 'insert from select' to
# show example usage of last_insert_rowid().
# an autoincrement column is used - if you need it in production please review
# your db model.
# before running, the sql's are checked for syntax errors against the db

include setup_example_env

const
  sqlInsertParent=sql"""insert into main.testtable (testcol1,testcol2) values 
                         (?,?); """
  sqlInsertChild=sql"""insert into main.testtable2 (val0,val1,val2)
                        select last_insert_rowid(),
                              datetime('now') , ? ; """
  
  testSelectSql = sql"""
                           SELECT c.val0  as child_fk2Parent
                                  ,c.val1 as child_val1
                                  ,c.val2 as child_val2
                                  ,t.id as parent_pk
                                  ,t.testcol1 as parent_c1
                                  ,t.testcol2 as parent_c2
                           FROM testtable2 c
                               INNER JOIN
                                  testtable t ON (t.id = c.val0);
                       """

var faultedCount = 0
for errs in db.validateSql(@[sqlInsertParent,sqlInsertChild,testSelectSql],returncode):
  inc faultedCount
  echo errs

if faultedCount > 0:
  echo "early exit.."
  quit(faultedCount)

var psInsertParent,psInsertChild,psSelect : PreparedStatement  

newPreparedStatement(db,sqlInsertParent,psInsertParent,returncode) 
newPreparedStatement(db,sqlInsertChild,psInsertChild,returncode) 
newPreparedStatement(db,testSelectSql,psSelect,returncode)                  

withTransaction(db, returncode):
  for i in countup(1,10):  # insert 10 parent/child sets 
    rawBind(psInsertParent,returncode):  
      var str = "teststr " & $i
      var str_childtab = "childtab" & $i
      discard psInsertParent.bindString(baseIdx,str)
      discard psInsertParent.bindFloat64(baseIdx+1,i.toFloat)
      # child part
      rawBind(psInsertChild,returncode):
        discard psInsertChild.bindString(baseIdx, str_childtab )

let resultSet = getResultSet(psSelect,returncode)
var colnames : seq[string]

resultSet.fetchColumnNames(colnames)
echo $colnames 

while hasRows(returncode):
  rawFetch(resultSet,returncode):
     var pk = resultSet.fetchInt64(colIdx)
     var date = resultSet.fetchString(colIdx+1)
     let str = resultSet.fetchString(colIdx+2)
     let str2 = resultSet.fetchString(colIdx+3)
     let tval = resultSet.fetchFloat64(colIdx+4)
     echo $pk & " " & $date & " " & str & " " & str2 & " " & $tval

cleanupAllocatedResources(db,returncode)
db.close(returncode)

