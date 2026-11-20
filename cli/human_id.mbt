///|
/// Curated lowercase wordlists aligned with `@changesets/cli` (`human-id`
/// `adjective-noun-verb` kebab-case changeset filenames, e.g. `brave-lions-dance`).
let human_id_adjectives : Array[String] = [
  "able", "bold", "brave", "bright", "calm", "clear", "clever", "cool", "crisp",
  "curious", "daring", "eager", "early", "easy", "fair", "fast", "fine", "firm",
  "fond", "free", "fresh", "gentle", "glad", "golden", "good", "grand", "great",
  "green", "happy", "honest", "jolly", "keen", "kind", "light", "lively", "lucky",
  "merry", "mild", "modern", "neat", "nice", "noble", "open", "plain", "polite",
  "proud", "quick", "quiet", "rare", "ready", "rich", "safe", "sharp", "shiny", "silent",
  "silver", "simple", "smart", "smooth", "soft", "solid", "steady", "sunny", "swift",
  "tender", "tidy", "warm", "wise",
]

///|
let human_id_nouns : Array[String] = [
  "ants", "badgers", "bears", "bees", "birds", "boats", "books", "clouds", "crabs",
  "cranes", "crows", "deer", "dogs", "dolphins", "doves", "ducks", "eagles", "elks",
  "falcons", "ferns", "finches", "fishes", "foxes", "frogs", "geese", "goats", "hawks",
  "herons", "horses", "jays", "kites", "koalas", "lambs", "larks", "lemurs", "lions",
  "llamas", "lynxes", "maples", "mice", "moles", "moons", "moths", "newts", "oaks",
  "otters", "owls", "pandas", "parrots", "pears", "pines", "ponies", "pumas", "quails",
  "rabbits", "ravens", "rivers", "robins", "seals", "sparrows", "stars", "storks",
  "swans", "tigers", "trees", "turtles", "waves", "whales", "wolves", "wrens", "yaks",
  "zebras",
]

///|
let human_id_verbs : Array[String] = [
  "bake", "beam", "bloom", "bounce", "build", "call", "camp", "care", "chat", "cheer",
  "climb", "code", "cook", "count", "craft", "dance", "dash", "dive", "draw", "dream",
  "drift", "drive", "echo", "fetch", "find", "float", "flow", "fly", "fold", "forge",
  "gather", "glide", "glow", "grow", "guide", "heal", "help", "hike", "hop", "hum",
  "join", "jump", "keep", "laugh", "lead", "leap", "learn", "lift", "listen", "look",
  "make", "march", "mend", "move", "open", "paint", "pause", "peek", "plan", "play",
  "race", "reach", "read", "rest", "ride", "rise", "roam", "roll", "row", "run",
  "sail", "save", "seek", "shape", "share", "shine", "sing", "sketch", "skip", "slide",
  "smile", "soar", "solve", "spark", "speak", "spin", "stand", "start", "step", "stroll",
  "study", "surf", "swim", "swing", "talk", "teach", "think", "trade", "train", "travel",
  "turn", "visit", "wait", "wake", "walk", "watch", "wave", "weave", "win", "wink",
  "wish", "work", "write", "zoom",
]

///|
let human_id_counter : Ref[UInt64] = Ref(0UL)

///|
fn splitmix64(x : UInt64) -> UInt64 {
  let mut z = x + 0x9e3779b97f4a7c15UL
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9UL
  z = (z ^ (z >> 27)) * 0x94d049bb133111ebUL
  z ^ (z >> 31)
}

///|
fn fnv1a64_bytes(bytes : Bytes) -> UInt64 {
  let mut hash = 0xcbf29ce484222325UL
  for b in bytes {
    hash = hash ^ b.to_int().to_uint64()
    hash = hash * 0x100000001b3UL
  }
  hash
}

///|
/// Generate a lowercase `adjective-noun-verb` changeset ID matching `@changesets/cli`
/// (`human-id` with `separator: "-"`, `capitalize: false`).
fn generate_human_id(seed : UInt64) -> String {
  let s1 = splitmix64(seed)
  let s2 = splitmix64(s1)
  let s3 = splitmix64(s2)
  let adj_idx = (s1 % human_id_adjectives.length().to_uint64()).to_int()
  let noun_idx = (s2 % human_id_nouns.length().to_uint64()).to_int()
  let verb_idx = (s3 % human_id_verbs.length().to_uint64()).to_int()
  human_id_adjectives[adj_idx] +
  "-" +
  human_id_nouns[noun_idx] +
  "-" +
  human_id_verbs[verb_idx]
}

///|
fn next_human_id(entropy_text : String, attempt : Int32) -> String {
  let seq = human_id_counter.val
  human_id_counter.val = seq + 1UL
  let time_bits = @env.now()
  let text_bits = fnv1a64_bytes(@utf8.encode(entropy_text))
  let seed = time_bits ^
    (text_bits * 0x9e3779b97f4a7c15UL) ^
    (seq << 16) ^
    attempt.to_uint64()
  generate_human_id(seed)
}
