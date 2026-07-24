#!/usr/bin/env bash

generate_password() {
  # Generate random string with base64. Prefer openssl, but fall back to
  # /dev/urandom + base64 (coreutils) on hosts where openssl isn't installed
  # (e.g. minimal WSL distros without internet access to install it).
  local base
  if command -v openssl >/dev/null 2>&1; then
    base=$(openssl rand -base64 32)
  else
    base=$(head -c 32 /dev/urandom | base64)
  fi

  # Replace any special chars not in our allowed set
  # First remove all special chars
  cleaned=$(echo "$base" | tr -dc 'a-zA-Z0-9')

  # Get length of cleaned string
  len=${#cleaned}

  # Select random positions to insert special chars
  num_special=$((RANDOM % 4 + 2)) # 2-5 special chars

  # Our allowed special chars
  special_chars='_=-%+*()'
  special_len=${#special_chars}

  # Insert special chars at random positions
  password="${cleaned:0:16}"
  # for ((i = 0; i < num_special; i++)); do
  #   # disallow last postion
  #   pos=$((RANDOM % 15))
  #   char_pos=$((RANDOM % special_len))
  #   special_char=${special_chars:char_pos:1}
  #   password="${password:0:pos}${special_char}${password:pos}"
  #   len=${#password}
  # done

  # Trim to desired length (16 characters)
  echo $password
}
