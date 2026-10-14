# Explain API contracts with intent and examples

Read this for API specs, routes, request/response schemas, authentication or public contract changes.
Use the repository's actual contract format/version (OpenAPI, API Blueprint, TypeSpec, protobuf,
GraphQL, handwritten apispec, etc.); do not convert it or assume all APIs are JSON over HTTP.
For RPC/GraphQL, adapt the operation inventory and request/result/error examples to that protocol.

## 1. Inventory all affected operations

Key HTTP operations by method + path, not path alone. Enumerate additions, modifications, removals,
and indirect impact through changed shared schemas, parameters, security requirements or generated
clients. Follow references and inherited path/operation settings; a diff confined to `components`
can affect many endpoints. Do not summarize only the first operation or every operation in the API.
For callbacks/webhooks, distinguish who sends the request from who receives it.

Use a compact inventory when several operations changed:

| Operation | Change | Purpose / reason | Implementation status | Compatibility |
| --- | --- | --- | --- | --- |
| Method + path | Added/changed/removed | Supported user action and evidenced reason | Spec-only/implemented/unverified | Concrete client effect or unknown |

For each operation, link to the relevant committed spec/source section. Distinguish the intended
contract, observed behavior and deployed behavior. A spec-only PR may have excellent examples but
cannot establish that a server returns them. If implementation diverges, describe the discrepancy.
For a removed operation, show the old contract/examples labelled **removed/previous behavior**,
explain affected callers and any evidenced replacement; do not offer it as a new working endpoint.

## 2. Explain design intent without inventing it

Explain which user/client action the operation supports and, where documented, why this boundary,
method, path, input/output shape, synchronous/asynchronous result or error contract was selected.
Tie decisions to a constraint such as an actual use case, client need, data model or ADR.
Do not reverse-engineer fictional author intent from REST conventions. Attribute explicit intent;
label analysis as inference and unresolved reasoning as “要確認”. Do not invent alternatives rejected
by the author. Shared reasons can be stated once and referenced by several operation sections.

## 3. Describe the request

For every affected operation, establish from the contract:
- Method/path/server or protocol operation; authentication scheme and required scopes/roles.
  Authentication and object/tenant-level authorization are separate questions.
- Path, query, header and cookie parameters: names, types, required/optional, relevant constraints,
  defaults, omitted versus null semantics and actual encoding/serialization.
- Request body: required or absent, media type, important fields, enums, nested structure and limits.
  Preserve directional `readOnly`/`writeOnly` semantics for the actual OpenAPI version.
- Conditional rules (mutually exclusive fields, update semantics, pagination, idempotency keys,
  concurrency headers) ONLY when defined and relevant; otherwise do not assert they exist.

Show a minimal valid request containing every required input and a meaningful variant if an optional
input or boundary is central to the change. Raw HTTP or curl is useful for HTTP; JSON body alone is
insufficient if required query/header/path data would be missing. State “リクエストボディなし” when
applicable instead of inventing `{}`. Use fake values complying with the schema and reserved example
hosts; never real tokens, personal/customer data or production IDs.

## 4. Describe the response and errors

For each operation include:
- Successful status/media type and relevant headers, response fields and their meaning.
- One complete minimal success example. For no-content responses (e.g. defined 204), explicitly
  show no body, not a JSON object. For asynchronous responses, describe the defined job/poll flow.
- Declared/implemented major errors: triggering condition, status/code/media type and a concrete
  representative error response. Explain changed error semantics and client recovery if specified.
- An additional example when central to the change: empty collection, next-page token, nullable
  field, alternate schema or newly rejected input. Do not flood the body with incidental variants.

Do not invent 400/401/403/404/409/429 or a generic error envelope because they seem conventional.
If errors, auth, requiredness or response shape are not defined, name the gap and evidence; ask for
missing contract decisions if needed for a usable description. Never present unknowns as examples.
RFC 9457 is an option only when the API uses Problem Details; do not retrofit it into PR prose.

## 5. Check examples against the actual contract

Prefer existing, sanitized contract examples or deterministic test fixtures. If constructing an
example, label it “仕様に基づく例（未実行）” and verify types, required fields, constraints, enums,
formats, composition (`oneOf`/`allOf`), references and serialization. Do not equate parseable JSON
with schema-valid input. Existing examples may themselves be stale; inspect rather than copy blindly.
Use the repo's permitted validator if available; otherwise report manual comparison and its limit.
No dependency install or production requests to validate a PR example without separate authorization.

For shared schemas, reuse a labelled common model if helpful, but retain each operation's own request,
status and response example or an unambiguous pointer to the exact common example. Do not allow
request/response fields from different operations to become mixed. Optional/null/omitted are distinct.

## 6. Explain impact and review focus

Compare old/new requiredness, field names/types, enum values, constraints, defaults, status/error
semantics, auth/scopes and removal/deprecation. Check affected clients, SDK generation and existing
data. “Field added” is not automatically safe: new required inputs, stricter validation, response
enums and changed defaults can break consumers. State known consumer impact and uncertainty rather
than a blanket backwards-compatibility guarantee.

When relevant, describe pagination/ordering, rate/resource limits, sensitive-field exposure,
object/property/function authorization, idempotency and retry semantics, rollout/migration order
and rollback limitations. These are review lenses, not demands to redesign the API. An absent limit
is an observation to flag where material, not permission to implement one.

## Illustrative operation section

This fictional example demonstrates the writing shape, NOT a fallback contract to copy. Assume the
source explicitly defines required `name` (1–100 characters), a server-generated UUID `id`, bearer
auth, `201` success, `400` for a missing name, and the stated rationale.

````markdown
### POST /projects — プロジェクト作成（仕様のみ）

画面から名前を指定してプロジェクトを作成する。設計メモでは、IDはサーバー側で発行し、
クライアントにID生成を要求しない方針としている。このPRにはサーバー実装を含まない。

- 認証: Bearer token。
- JSON body: `name` は必須の文字列（1〜100文字）。`id` は入力しない。
- 例は仕様に基づく未実行の例。

**リクエスト**
```http
POST /projects HTTP/1.1
Host: api.example.com
Authorization: Bearer <TOKEN>
Content-Type: application/json

{"name":"sample-project"}
```

**成功レスポンス**
```http
HTTP/1.1 201 Created
Content-Type: application/json

{"id":"123e4567-e89b-42d3-a456-426614174000","name":"sample-project"}
```

**エラー例: nameを省略した場合**
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{"code":"INVALID_NAME","message":"name is required"}
```
````

Supply equivalent evidence-based sections for every other affected operation. Never copy these
names, statuses or error semantics into a different API.

## Primary sources and scope

- [OpenAPI 3.1.1](https://spec.openapis.org/oas/v3.1.1.html): Operation, Parameter, Request Body,
  Response, Example and Security Requirement Objects. Examples should match schemas and serialized
  forms; inherited settings and references matter. Consult the target's version, not this version
  blindly (e.g. OpenAPI 3.0 and 3.1 differ in schema/directional semantics).
- [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457.html): Problem Details, `application/problem+json`
  and security considerations. A supported error format, not mandatory for all APIs.
- [Google AIP-180](https://google.aip.dev/180): source, wire and semantic compatibility; required
  inputs, removal, changed defaults and response values. Guidance assumes particular API/transport
  and consumer conditions; apply the repo's contract rather than importing Google policy.
- [OWASP API Security Top 10 (2023)](https://owasp.org/API-Security/editions/2023/en/0x11-t10/):
  authorization, exposure, resource use and endpoint inventory as risk lenses, not proof of safety.
