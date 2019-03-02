import options,strutils
# bulk bind example 

include setup_example_env 
# create a in memory database with connection db

type
    TestObj* = object
      id :  Option[int64]  # pk set by db
      str : Option[string]
      val : Option[float64]
  
proc bindColsCb(ps : PreparedStatement, bindIdx : int, bind_obj : var TestObj) {.inline.} =
  discard ps.bindString(bindIdx,bind_obj.str)
  discard ps.bindFloat64(bindIdx+1,bind_obj.val)

var container : seq[TestObj]
newSeq(container,6)
  
for i in countup(0,container.len-1): # init seqence
  container[i] = TestObj(str : option("teststring.." & $i), val: option(i.float64) )
  
var numrows = 0.int
  
var ps : PreparedStatement  
newPreparedStatement(db,sql"""insert into main.testtable (testcol1,testcol2) values 
                       (?,?),(?,?),(?,?); """, ps,returncode) 
                       # bulk insert 3 rows at once
  
withFinalisePreparedStatement(ps,returncode):  
# after leaving this block the preparedStatement will be finalized                                     
  withTransaction(db, returncode):
  # after this block a commit is performed unless a exception is thrown,
  # forceRollback(returncode) is executed  or an error was propagated from the backend
    numrows = bulkBind(ps,container,bindColsCb,2,returncode)
  if returncode.evalHasError:
    echo $returncode

let oneRow = queryOneRow(db,sql"select count(*) as rowcount from main.testtable;",returncode,1)
if returncode.evalHasError:
    echo $returncode  

assert( parseInt(oneRow[0]) == 6,"error, 6 rows expected")
echo oneRow[0] & " rows inserted"
