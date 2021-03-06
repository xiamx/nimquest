import std/httpclient
import std/json
import std/htmlparser
import std/xmltree
import std/db_sqlite
import std/times
import std/strutils
import std/os
import std/re
include config

type MastodonClient = tuple
  httpClient: HttpClient
  apiRoot: string

proc sendHeartBeat() = 
  if cronitorKey != "":
    let client = newHttpClient()
    discard client.getContent("https://cronitor.link/p/" & cronitorKey & "/" & cronitorMonitor & "?message='alive'")

proc createMastodonClient(apiRoot: string, accessToken: string): MastodonClient =
  let client = newHttpClient()
  client.headers = newHttpHeaders({ "Authorization": "Bearer " & accessToken })
  return (client, apiRoot)

proc getNotifications(client: MastodonClient): JsonNode =
  let response = client.httpClient.getContent(client.apiRoot & "/api/v1/notifications?exclude_types%5B%5D=reblog&exclude_types%5B%5D=follow&exclude_types%5B%5D=favourite&limit=100")
  return parseJson(response)

proc postStatus(client: MastodonClient, data: MultipartData): JsonNode =
  return parseJson(client.httpClient.postContent(client.apiRoot & "/api/v1/statuses", multipart=data))

proc parseStatusText(status: JsonNode): string =
  let htmlNode = parseHtml(status["content"].getStr())
  return strip(innerText(htmlNode))

proc removeSelfReference(text: string): string =
  return text.replace("@nimquest@hello.2heng.xin", "").replace("@nimquest", "")

proc removeMentions(text: string): string =
  return text.replacef(re"\$\S+@\S+", "").replacef(re"@\S+@\S+", "").removeSelfReference()

proc markNotificationProcessed(db: DbConn, statusId: string, notificationDT: DateTime): void =
  db.exec(sql"INSERT INTO processed_notifications (status_id, created_at) VALUES (?, ?)", statusId, $notificationDT)

proc isNotificationProcessed(db: DbConn, statusId: string): bool =
  let val = db.getValue(sql"SELECT 1 FROM processed_notifications WHERE status_id = ?", statusId)
  return val != ""

proc checkNotification() =
  let db = open("db.sqlite3", "", "", "")
  let mastodonClient = createMastodonClient(apiRoot, clientAccessToken)

  var payloadNode: JsonNode
  try:
    payloadNode = mastodonClient.getNotifications()
  except ProtocolError:
    echo "[E] Failed to check notifications"
    return

  let dtFormat = "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'"

  for notification in payloadNode:
    let notificationType = notification["type"].getStr()
    let notificationDT = parse(notification["created_at"].getStr(), dtFormat).utc

    if not notification.contains("status"):
      continue
    let status = notification["status"]
    if not status.contains("id") or status.kind != JObject:
      echo "skipping non status notification "  & notification["id"].getStr()
      continue
    let statusId = status["id"].getStr()
    if db.isNotificationProcessed(statusId):
      continue

    let visibility = status["visibility"].getStr()
    if notificationType == "mention" and visibility == "direct":
      let inReplyToId = status["in_reply_to_id"].getStr()
      if status["mentions"].len > 1:
        continue
      elif inReplyToId == "":
        # this is a probably new request for answer
        let askerUserName = status["account"]["acct"].getStr()
        let text = status.parseStatusText()
        let matches = findAll(text, re"\$\S+@\S+")
        if matches.len != 1:
          # skip, no target
          # TODO: maybe send instructions back?
          continue

        let answererUsername = matches[0].replacef(re"\$(\S+@\S+)", "$1")

        echo "asker: " & askerUserName & "answerer: " & answererUsername
        if db.getValue(sql"SELECT count(*) FROM rel where asker=? and answerer=? and allow=0", askerUserName, answererUsername) != "0":
          echo "[W]Answerer: " & answererUsername & " already banned asker: " & askerUserName
          db.markNotificationProcessed(statusId, notificationDT)
          continue

        if db.getValue(sql"SELECT count(*) FROM optouts where username=?", answererUsername) != "0":
          echo "[W]Answerer: " & answererUsername & " opted out"
          db.markNotificationProcessed(statusId, notificationDT)
          continue

        var data = newMultipartData()
        let question = text.removeSelfReference().replacef(re"\$(\S+@\S+)", "@$1")
        data["status"] = question
        data["spoiler_text"] = "??????????????????????????????????????????????????? nimquest ?????????\n?????? NO ??????????????????????????????\n?????? STOP ???????????????????????????"
        data["visibility"] = "direct"

        let postedStatus = mastodonClient.postStatus(data)
        db.exec(sql"INSERT INTO questions (status_id, question, asker, answerer, created_at) VALUES (?, ?, ?, ?, ?)", postedStatus["id"].getStr(), question.removeMentions(), askerUserName, answererUsername, $notificationDT)
        db.markNotificationProcessed(statusId, notificationDT)

        echo "[Q][Answerer: " & answererUsername & "]" & ": " & question
      elif inReplyToId != "":
        echo "[Get reply for] " & inReplyToId
        # this is a reply to a question
        let question = db.getValue(sql"SELECT question FROM questions WHERE status_id=?", inReplyToId)
        let asker = db.getValue(sql"SELECT asker FROM questions WHERE status_id=?", inReplyToId)
        let answererUsername = status["account"]["acct"].getStr()
        let answer = status.parseStatusText().removeMentions().strip()

        if toUpperAscii(answer) == "STOP":
          db.exec(sql"INSERT OR IGNORE INTO optouts (username, created_at) VALUES (?, ?)", answererUsername, $notificationDT)
          var data = newMultipartData()
          data["status"] = "@" & answererUsername & " ????????????"
          data["visibility"] = "direct"
          data["in_reply_to_id"] = statusId

          discard mastodonClient.postStatus(data)
          echo "[D][Answerer: " & answererUsername & "]"
        elif toUpperAscii(answer) == "NO":
          db.exec(sql"INSERT INTO rel (answerer, asker, allow) VALUES (?, ?, ?) ON CONFLICT (answerer, asker) DO UPDATE SET allow=0", answererUsername, asker, 0)
          var data = newMultipartData()
          data["status"] = "@" & answererUsername & " ????????????"
          data["visibility"] = "direct"
          data["in_reply_to_id"] = statusId

          discard mastodonClient.postStatus(data)
          echo "[B][Answerer: " & answererUsername & "][Asker: " & asker & "]"
        else:
          var data = newMultipartData()
          data["status"] = "@" & answererUsername & " ??????????????????????????????" & question & "\n\n" & answer & "\n\n" & "#nimquest #????????????"
          data["visibility"] = "public"

          discard mastodonClient.postStatus(data)
          echo "[A][Answerer: " & answererUsername & "]" & ": " & answer
        db.exec(sql"UPDATE questions SET answer=?, answerer=?, answered_at=? WHERE status_id=?", answer, answererUsername, $notificationDT, inReplyToId)
        db.markNotificationProcessed(statusId, notificationDT)

  db.close()
  

when isMainModule:
  while true:
    echo "[L] Checking notifications..."
    checkNotification()
    sendHeartBeat()
    sleep(30000)

