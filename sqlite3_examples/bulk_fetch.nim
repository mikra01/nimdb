# example of bulk fetch

include bulk_bind  # get the database filled with 6 rows

# read now the rows from the previous example

proc incarnateTstObjCb( ps: PreparedStatement, firstidx : int,
                         maxcols : int, outobj : var TestObj ) {.inline.} =
  # this is the callback to populate the obj  -
  # we are not consuming possible errorcodes while fetching
  var rc : RCode 
  outobj = TestObj( id  : ps.fetchInt64Opt(firstidx), 
                    str : ps.fetchString(firstidx+1,rc),
                    val : ps.fetchFloat64Opt(firstidx+2) ) 

newPreparedStatement(db,sql""" select id,testcol1, testcol2 
                               from main.testtable order by id desc ; """, ps,returncode) 
newSeq(container,3)

var rowcount : int = 0

withFinalisePreparedStatement(ps,returncode):
  let rs = getResultSet(ps,returncode)
  # if not in WAL mode we have a read-lock here
  if hasRows(returncode):
    rowcount = rowcount + fetchRows(rs,container, incarnateTstObjCb,returncode) 
  assert( unsafeGet(container[0].id) == 6 ,"id number 6 expected")
  echo container
  # read next 3 rows
  if hasRows(returncode):
    rowcount = rowcount + fetchRows(rs,container, incarnateTstObjCb,returncode) 
  assert(hasRows(returncode) == false, "we expect no more rows here" )

echo container

when isMainModule:
    db.close(returncode)
    if returncode.evalHasError:
      echo $returncode    