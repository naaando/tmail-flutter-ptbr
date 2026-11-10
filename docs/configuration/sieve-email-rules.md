# Email rules on JMAP for Sieve servers (Stalwart)

The "Email rules" settings have two backends. The webmail picks one per
account from the JMAP session:

| Session announces | Backend | API |
|---|---|---|
| `com:linagora:params:jmap:filter` | Linagora (unchanged, keeps priority) | `Filter/get`, `Filter/set` |
| `urn:ietf:params:jmap:sieve` **and** `urn:ietf:params:jmap:blob` | Sieve | `SieveScript/get`, `SieveScript/validate`, `SieveScript/set`, `Blob/upload`, `Blob/get` |
| neither | menu hidden | - |

Code: `EmailRulesBackend.resolve()` (`lib/features/manage_account/domain/model/email_rules_backend.dart`).

The Sieve backend talks to the same JMAP endpoint as the rest of the webmail,
authenticated as the signed-in user. There is no extra service and no
administrative credential in the browser. Rules are stored on the server and
run at delivery, with the webmail closed.

## Compatibility

Checked on 2026-11-10 against `stalwartlabs/stalwart:v0.16`
(digest `sha256:c429b311c93db5606598abc1c68225a85a6953183848ae01bee9c6a98885836c`),
which announces `implementation: "Stalwart v1.0.0"`, `maxSizeScript: 102400`,
`maxNumberScripts: 100` and the extensions used below.

Server behaviour the implementation depends on (all reproduced on that
version):

- Only one script is active per account. Activating one deactivates the others.
- `VacationResponse` is a script named `vacation`. Turning the automatic reply
  on activates it (and deactivates the rules); turning it off leaves **no**
  script active.
- `SieveScript/set` compiles the script and answers `notCreated`/`notUpdated`
  with `invalidScript`; `onSuccessActivateScript` is only applied on success.
- `ifInState` is enforced (`stateMismatch`). The state also changes when the
  automatic reply changes.
- An active script cannot be destroyed (`scriptIsActive`).
- `SieveScript/validate` does not accept a `#creationId` blob reference, so the
  blob is uploaded first, then validated, then stored (three requests).
- `:mailboxid` requires `mailbox` in `require` on Stalwart.
- `i;unicode-casemap` works although it is not listed in `sieveExtensions`.
- `implementation` is announced in the session-level `urn:ietf:params:jmap:sieve`
  capability (as RFC 9661 defines), not in the account capability; the comparator
  choice reads it from there.

## The managed script

The webmail owns one script, `twake-mail-rules`. It never reads other scripts
as rules and never changes, deactivates or deletes them.

The script starts with a metadata comment that holds the visual rules as JSON
(`# twake-mail-rules: {...}`); the code below it is generated from that JSON.
On read, the webmail regenerates the script from the metadata and compares it
with the stored content (line endings and trailing blanks ignored):

- equal: the rules are editable;
- different, or JSON missing/invalid: the rules are **read-only** in the
  webmail and the script is left untouched (`modifiedExternally`);
- a `twake-mail-rules` script without metadata: read-only (`nameConflict`).

Nothing is stored only in the browser. Code: `SieveRulesCodec`
(`rule_filter/lib/sieve/sieve_rules_codec.dart`).

### Mapping

| Editor | Sieve |
|---|---|
| All / any of the conditions | `allof(...)` / `anyof(...)` |
| From, To, Cc | header `from`, `to`, `cc` |
| Recipient | headers `to` and `cc` |
| Subject | header `subject` |
| contains / does not contain | `header :contains` / `not header :contains` |
| is exactly / is not exactly (address fields) | `anyof(address :all :is, header :is)` and its `not` |
| is exactly / is not exactly (subject) | `header :is` and its `not` |
| comparator | `i;unicode-casemap` on Stalwart, `i;ascii-casemap` elsewhere (stored in the metadata) |
| Move to folder, Mark as spam | `fileinto :mailboxid "<id>" "INBOX"` (`fileinto`, `mailbox`, `mailboxid`) |
| Mark as seen, Star it, keywords | `addflag [...]` (`imap4flags`) |
| Reject it | `discard; stop;` (silently dropped, no bounce) |
| Do not apply the following rules | `stop;` |
| Disabled rule | kept in the metadata, no code generated |
| Forward to | not offered by the editor (unchanged) |

Values are quoted per RFC 5228: `\` and `"` are escaped, CR/LF removed,
Unicode kept as UTF-8.

Semantics worth knowing:

- Rules run top to bottom. Without `stop`, every matching rule applies.
- `addflag` accumulates: flags from a rule also reach later folders and the
  default delivery (implicit keep). JMAP keywords belong to the message, so a
  message filed in two folders has one set of flags.
- A message matching no rule, or only flag rules, is delivered as usual.
- Folders are referenced by id, so renaming a folder keeps the rule working.
  If the folder is deleted, Stalwart falls back to `INBOX`; mail is never lost.
- Extensions are checked against `sieveExtensions` before saving. An action the
  server lacks is removed from the editor with an explanation, and a rule that
  still uses it fails to save with the missing extension named.

## Coexistence

A write activates the managed script **only when no other script is active**.
Otherwise the rules are saved inactive and the page explains why:

- automatic reply on: "rules are paused"; once it is turned off, the page
  offers "Activate rules" (nothing else is active then);
- another client's filter active: its name is shown; the webmail does not
  deactivate it.

Turning the automatic reply on from the webmail still deactivates the rules,
because the server does it. Reconciling both into one script is not in scope.

## Writes and failures

Every write: generate → size check against `maxSizeScript` → `Blob/upload` →
`SieveScript/validate` → `SieveScript/set` with `ifInState` → read back and
compare. A 200 response alone is not success:

| Failure | Result |
|---|---|
| `stateMismatch` | "changed in another session", list reloaded, nothing written |
| script edited elsewhere | read-only notice, add/edit/reorder hidden, script untouched |
| `invalidScript`, `notCreated`, `notUpdated`, quota | server message shown, nothing activated |
| stored rules differ from the ones sent | "server did not confirm", list reloaded |
| script too large / extension missing | refused before any request |

Rules are not applied to messages already in the mailbox.

## Rollback

The feature is client-side only; the server needs no configuration.

1. Redeploy the previous webmail image. The Linagora backend is untouched and
   Stalwart sessions simply hide the menu again.
2. Rules already stored keep running on the server. To stop them for an
   account, deactivate or delete `twake-mail-rules` with any ManageSieve client
   (port 4190) as that user, or through the Stalwart admin UI.
3. Other scripts (automatic reply, filters from other clients) were never
   modified, so nothing else needs restoring.
