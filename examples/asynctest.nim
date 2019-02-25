import httpclient, os, times, strutils
import asyncdispatch, asyncstreams

proc `$`(dt: DateTime): string =
  dt.format("uuuu-MM-dd HH:mm:ss'.'fffffffffzz")

proc `$`(dur: Duration): string =
  $dur.seconds & "." & intToStr(dur.nanoseconds, 9)

proc start(i: int, url: string) {.async.} =
  var j = 1
  var client: AsyncHttpClient
  while true:
    if j > 5:
      break
    let t0 = utc(now())
    client = newAsyncHttpClient()
    var h = await client.get(url)
    var bytes = 0
    var hasData: bool
    var buf: string
    var body: string
    let t1 = utc(now())
    buf = ""
    echo intToStr(i,2), " ", intToStr(j,4), " ", t1, " ", h.status, " memory: ", 
          formatSize getOccupiedMem(), " bytes: ", bytes, " duration: ", t1 - t0
    client.close()
    await sleepAsync(5000)
    inc(j)

proc test(url: string) {.async.} =
  echo "spawning: ", 0
  await start(0, url)

let url = "https://jsonplaceholder.typicode.com/photos"
waitFor(test(url))
try:
  GC_fullcollect()
  echo formatSize getOccupiedMem()
except:
  echo getCurrentExceptionMsg()
  discard