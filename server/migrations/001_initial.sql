CREATE TABLE IF NOT EXISTS countries (
  code text PRIMARY KEY CHECK (code ~ '^[A-Z]{2}$'),
  name text NOT NULL
);
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE CHECK (email = lower(email)),
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  password_hash text NOT NULL,
  home_country text NOT NULL REFERENCES countries(code),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
CREATE TABLE IF NOT EXISTS country_admins (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  country_code text NOT NULL REFERENCES countries(code),
  PRIMARY KEY (user_id, country_code)
);
CREATE TABLE IF NOT EXISTS country_follows (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  country_code text NOT NULL REFERENCES countries(code),
  PRIMARY KEY (user_id, country_code)
);
CREATE TABLE IF NOT EXISTS posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  species text NOT NULL CHECK (species IN ('dog', 'cat')),
  sex text NOT NULL CHECK (sex IN ('female', 'male', 'unknown')),
  age_months integer NOT NULL CHECK (age_months BETWEEN 0 AND 360),
  size text NOT NULL CHECK (size IN ('small', 'medium', 'large')),
  source text NOT NULL CHECK (source IN ('shelter', 'street', 'family')),
  country_code text NOT NULL REFERENCES countries(code),
  city text NOT NULL CHECK (char_length(city) BETWEEN 1 AND 100),
  story text NOT NULL CHECK (char_length(story) BETWEEN 20 AND 6000),
  contact_email text NOT NULL,
  vaccinated boolean NOT NULL DEFAULT false,
  neutered boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'adopted', 'hidden')),
  created_at timestamptz(3) NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS posts_feed ON posts(country_code, created_at DESC, id DESC) WHERE status = 'available';
CREATE INDEX IF NOT EXISTS posts_author ON posts(author_id);
CREATE TABLE IF NOT EXISTS photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  position integer NOT NULL CHECK (position BETWEEN 0 AND 5),
  data bytea NOT NULL CHECK (octet_length(data) BETWEEN 1 AND 1572864),
  UNIQUE(post_id, position)
);
CREATE TABLE IF NOT EXISTS likes (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  PRIMARY KEY(user_id, post_id)
);
CREATE INDEX IF NOT EXISTS likes_post ON likes(post_id);
CREATE TABLE IF NOT EXISTS reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 5 AND 1000),
  resolved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, post_id)
);
CREATE TABLE IF NOT EXISTS moderation_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid REFERENCES users(id) ON DELETE SET NULL,
  post_id uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  previous_status text NOT NULL,
  new_status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
