///|
fn property(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn schema_issue(
  value : Json,
  schema : Json,
  root : Json,
  path : String,
) -> String? {
  if property(schema, "$ref") is String(reference) {
    return schema_issue(
      value,
      property(property(root, "$defs"), reference[8:].to_owned()),
      root,
      path,
    )
  }
  if property(schema, "oneOf") is Array(choices) {
    let matches = choices.filter(s => schema_issue(value, s, root, path) is None)
    if matches.length() != 1 {
      return Some(path + ": invalid value or object fields")
    }
  }
  if schema is Object(fields) &&
    fields.get("const") is Some(expected) &&
    value != expected {
    return Some(path + ": unexpected value")
  }
  if property(schema, "enum") is Array(choices) && !choices.contains(value) {
    return Some(path + ": unsupported value")
  }
  if property(schema, "type") is String(kind) {
    let valid = match (kind, value) {
      ("object", Object(_))
      | ("array", Array(_))
      | ("string", String(_))
      | ("boolean", True)
      | ("boolean", False) => true
      _ => false
    }
    if !valid {
      return Some(path + ": expected " + kind)
    }
  }
  match value {
    Object(fields) => {
      if property(schema, "required") is Array(required) {
        for key in required {
          if key is String(key) && !fields.contains(key) {
            return Some(path + "." + key + ": required field")
          }
        }
      }
      let props = property(schema, "properties")
      for key, item in fields {
        let child = property(props, key)
        if child != Json::null() {
          if schema_issue(item, child, root, path + "." + key) is Some(issue) {
            return Some(issue)
          }
        } else {
          match property(schema, "additionalProperties") {
            False => return Some(path + "." + key + ": unknown field")
            Object(_) as child =>
              if schema_issue(item, child, root, path + "." + key)
                is Some(issue) {
                return Some(issue)
              }
            _ => ()
          }
        }
      }
    }
    Array(items) => {
      if property(schema, "minItems") is Number(min, ..) &&
        items.length().to_double() < min {
        return Some(path + ": too few items")
      }
      let child = property(schema, "items")
      for i, item in items {
        if schema_issue(item, child, root, path + "[\{i}]") is Some(issue) {
          return Some(issue)
        }
      }
    }
    String(text) =>
      if property(schema, "minLength") is Number(min, ..) &&
        text.length().to_double() < min {
        return Some(path + ": empty string")
      }
    _ => ()
  }
  if property(schema, "allOf") is Array(rules) {
    for rule in rules {
      if schema_issue(value, property(rule, "if"), root, path) is None {
        if schema_issue(value, property(rule, "then"), root, path)
          is Some(issue) {
          return Some(issue)
        }
      }
    }
  }
  None
}
