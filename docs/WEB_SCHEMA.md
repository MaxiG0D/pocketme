# Web app CloudKit schema

Private database. Create these in the Development environment, then deploy to Production.
The apps create the zones (`WebLibrary`, `WebSaves`); the web only reads `WebArticle` and writes `WebChange` / `SaveRequest`.

**WebArticle** (zone `WebLibrary`, written by the apps; record name = article UUID)
articleID String, url String, title String, siteName String, author String, excerpt String, leadImageURL String,
status String, body String, wordCount Int(64), readingMinutes Int(64), savedAt Date/Time, archived Int(64),
isFavorite Int(64), thumbnail Asset.
Indexes: `recordName` Queryable; `savedAt` Queryable + Sortable.

**WebChange** (zone `WebSaves`, written by the web, deleted by the apps after applying)
articleID String, action String (`archive` | `unarchive` | `favorite` | `unfavorite` | `delete`), at Date/Time.
Index: `recordName` Queryable.
