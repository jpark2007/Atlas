# 07 — Social & Collaboration

## Accounts

- Separate login per person (Supabase auth). Everyone owns their own Atlas.
- Built to support **individual users** beyond just the two of us.

## Friends

- Add friends (by username/email).
- View a friend's **availability** — free/busy overlay; answer "when are we both free?"

## Shared spaces

- A space can be **shared** with members (e.g. a "Roommates" or shared "School" space).
- Members see and contribute to the space's projects/items per their role.

## Shared / group projects

- Projects can be **group projects**: shared **tasks**, shared **scheduling**, shared **meetings**.
- Useful for class group work, side projects, planning with friends.

## Availability

- Derived from each user's calendar (busy blocks), respecting privacy — show free/busy, not necessarily event details unless shared.

## Permissions

- Enforced server-side with Postgres Row-Level Security: users only see spaces/projects/items they own or are members of.
- Roles (owner/member) per space and per project.

## Open questions

- Granularity of availability sharing (full details vs. busy-only, per friend).
- Invitations/requests flow (accept/decline).
- Notifications for shared changes.
