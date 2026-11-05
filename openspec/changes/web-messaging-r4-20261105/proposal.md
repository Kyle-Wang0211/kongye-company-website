# Web private messaging through the existing R4 service

The authenticated community web needs an inbox and profile-originated conversation route connected to the existing R4 messaging service. The baseline is 02dafd143f598844339800e61f6a5f1972b982cb. The existing R4 PostgreSQL seven-case acceptance is reused as backend evidence. Its production activation is owned by the backend operator.

The messaging module owns `web_messaging_repository.dart`, `web_messaging_entry.dart`, `web_messages_page.dart`, `web_conversation_page.dart` and their focused tests. The main entry, public profiles, work details, shared social API and other features remain separate integration ownership domains.

The module uses the existing `WebSocialApi` R4 caller RPC and authenticated send endpoint. Supabase's pinned official Flutter SDK supplies paged inbox SELECTs and private Realtime Postgres Changes subscriptions. Both channels and data access use the current account's JWT and server membership RLS. Reconnects and change events invalidate history. The client reads authoritative history before showing delivered content.

A message submission keeps its nonce for explicit retries during this repository's lifetime. Unknown transport outcomes first reconcile `pw_dm_status` under that nonce. A terminal confirmed delivery permits a later intentional identical message with a new nonce. Pending machine processing, technical retry, genuine content review, rejection and delivered messages have distinct presentation. Technical errors remain technical retry states. Receipt timestamps for pending submissions are local submission times. Delivered message content and timestamps come from server history.

History loads include monotonic read-cursor advancement for received messages. Withdrawal, message reports and bilateral desired block state call the existing R4 RPCs. A 600-unit send limit matches the existing transport and backend. Account changes hide private routes, reject late results and prevent mutations through an old account repository.

`WebMessagingEntry` supports an injected repository for offline tests. Normal construction derives endpoints and caller identity from the existing regional application configuration and official signed-in Supabase client. The build gate `PW_WEB_MESSAGING_READY` stays false until the backend owner verifies the actual SQL, provider and route. Main/profile integration uses the same component, with optional peer identity for pair creation.

Acceptance uses the pinned cached Flutter SDK with `--no-pub`. Focused repository, actual HTTP adapter generation and widget tests cover receipt states, stable nonce retries, single-flight sends, pagination, auth changes, normal entry navigation, private history invalidation, state presentation and responsive layouts. The main owner performs the final integrated browser and live verification after the backend is ready.

The existing R4 source, region and namespace are immutable inputs. Installation of dependencies, protocol or provider replacement, mobile deployment and writes to other modules are outside this implementation. A mismatched account, unbound backend, malformed cursor or actual transport failure fails closed at the affected action and preserves the current draft.
