# artificial foreign key example with 
# 'insert from select' to
# show example usage of last_insert_rowid().
# an autoincrement column is used - only recommended
# for testing purpose.

include setup_example_env

var psInsertParent,psInsertChild,psSelect : PreparedStatement  

newPreparedStatement(db,sql"""insert into main.testtable (testcol1,testcol2) values 
                               (?,?); """, psInsertParent,returncode) 

newPreparedStatement(db,sql"""insert into main.testtable2 (val0,val1,val2)
                               select last_insert_rowid(),
                                      datetime('now') , ? ; """, 
                                       psInsertChild,returncode) 
const 
    testSelectSql = sql"""
                           SELECT c.val0
                                  ,c.val1
                                  ,c.val2
                                  ,t.id
                                  ,t.testcol1
                                  ,t.testcol2
                           FROM testtable2 c
                               INNER JOIN
                                  testtable t ON (t.id = c.val0);
                       """
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
