# sets up the example environment for the examples
# the db contains one table (testtable (id,testcol1 text, testcol2 double ) )
# and one view (testview)

import src/sqlite3/nimdb_sqlite3
import db_sqlite

var returncode : RCode = (vendorcode: 0.int , errStr: "")
var syserrc : int
let db : nimdb_sqlite3.DbConn = open(":memory:", "", "",returncode,syserrc)

if returncode.evalHasError:
  echo $returncode.errStr
  echo "io_os_errcode: " & $syserrc
  quit(returncode.vendorcode)

incarnateDbFromTemplate(db,"dbtemplate/example_sqlite3db.db",returncode)

if returncode.evalHasError:
    echo $returncode
    quit(returncode.vendorcode)
