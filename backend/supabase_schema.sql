-- Cartridge backend schema for Supabase (Postgres).
-- Run this in Supabase Dashboard -> SQL Editor, or point DATABASE_URL at
-- Supabase and run `python -m app.init_db` instead.

create table if not exists users (
    id            bigserial primary key,
    email         varchar(255) not null unique,
    password_hash varchar(255) not null,
    is_admin      boolean not null default false,
    created_at    timestamp not null default (now() at time zone 'utc')
);

create table if not exists games (
    id               bigserial primary key,
    slug             varchar(200) not null unique,
    title            varchar(200) not null,
    description      text not null default '',
    author           varchar(200) not null default '',
    license_spdx     varchar(50)  not null default 'MIT',
    source_url       varchar(500) not null default '',
    play_url         varchar(500) not null default '',
    package_url      varchar(500) not null default '',
    package_sha256   varchar(64)  not null default '',
    thumbnail_url    varchar(500) not null default '',
    poster_style     varchar(40)  not null default 'TAP',
    accent_top       varchar(20)  not null default '#0B1020',
    accent_bottom    varchar(20)  not null default '#1B2350',
    bundled          boolean not null default false,
    status           varchar(20) not null default 'candidate',
    orientation      varchar(20) not null default 'any',
    review_note      varchar(300) not null default '',
    qa_status        varchar(20) not null default '',
    qa_keys          varchar(120) not null default '',
    qa_note          varchar(300) not null default '',
    tags             varchar(300) not null default '',
    initial_likes    integer not null default 0,
    initial_comments integer not null default 0,
    stars            integer not null default 0,
    created_at       timestamp not null default (now() at time zone 'utc'),
    updated_at       timestamp not null default (now() at time zone 'utc')
);
create index if not exists idx_games_status on games (status);

create table if not exists likes (
    id         bigserial primary key,
    user_id    bigint not null references users(id) on delete cascade,
    game_id    bigint not null references games(id) on delete cascade,
    created_at timestamp not null default (now() at time zone 'utc'),
    unique (user_id, game_id)
);

create table if not exists saves (
    id         bigserial primary key,
    user_id    bigint not null references users(id) on delete cascade,
    game_id    bigint not null references games(id) on delete cascade,
    created_at timestamp not null default (now() at time zone 'utc'),
    unique (user_id, game_id)
);

create table if not exists collections (
    id         bigserial primary key,
    user_id    bigint not null references users(id) on delete cascade,
    name       varchar(120) not null,
    created_at timestamp not null default (now() at time zone 'utc')
);

create table if not exists collection_items (
    id            bigserial primary key,
    collection_id bigint not null references collections(id) on delete cascade,
    game_id       bigint not null references games(id) on delete cascade,
    created_at    timestamp not null default (now() at time zone 'utc'),
    unique (collection_id, game_id)
);

create table if not exists comments (
    id         bigserial primary key,
    user_id    bigint not null references users(id) on delete cascade,
    game_id    bigint not null references games(id) on delete cascade,
    body       text not null,
    created_at timestamp not null default (now() at time zone 'utc')
);
create index if not exists idx_comments_game on comments (game_id);

create table if not exists reports (
    id         bigserial primary key,
    user_id    bigint references users(id) on delete set null,
    game_id    bigint not null references games(id) on delete cascade,
    reason     varchar(30) not null,
    details    text not null default '',
    status     varchar(20) not null default 'open',
    created_at timestamp not null default (now() at time zone 'utc')
);
create index if not exists idx_reports_status on reports (status);

create table if not exists submissions (
    id           bigserial primary key,
    title        varchar(200) not null,
    description  text not null default '',
    url          varchar(500) not null,
    license_spdx varchar(50) not null,
    image_url    varchar(500) not null default '',
    email        varchar(255) not null default '',
    status       varchar(20) not null default 'pending',
    created_at   timestamp not null default (now() at time zone 'utc')
);
create index if not exists idx_submissions_status on submissions (status);
