# Function to log start of a operation
step_log() {
  message=$1
  printf "\n\033[90;1m==> \033[0m\033[37;1m%s\033[0m\n" "$message"
}

# Function to log result of a operation
add_log() {
  mark=$1
  subject=$2
  message=$3
  if [ "$mark" = "$tick" ]; then
    printf "\033[32;1m%s \033[0m\033[34;1m%s \033[0m\033[90;1m%s\033[0m\n" "$mark" "$subject" "$message"
  else
    printf "\033[31;1m%s \033[0m\033[34;1m%s \033[0m\033[90;1m%s\033[0m\n" "$mark" "$subject" "$message"
  fi
}

# Function to remove extensions
remove_extension() {
  extension=$1
  sudo sed -i '' "/$extension/d" "$ini_file"
  sudo rm -rf "$ext_dir"/"$extension".so 
}

# Function to setup extensions
add_extension() {
  extension=$1
  install_command=$2
  prefix=$3
  if ! php -m | grep -i -q -w "$extension" && [ -e "$ext_dir/$extension.so" ]; then
    echo "$prefix=$extension" >>"$ini_file" && add_log "$tick" "$extension" "Enabled"
  elif php -m | grep -i -q -w "$extension"; then
    add_log "$tick" "$extension" "Enabled"
  elif ! php -m | grep -i -q -w "$extension"; then
    (eval "$install_command"  && add_log "$tick" "$extension" "Installed and enabled") ||
    add_log "$cross" "$extension" "Could not install $extension on PHP $semver"
  fi
}

# Fuction to get the PECL version
get_pecl_version() {
  extension=$1
  stability=$2
  pecl_rest='https://pecl.php.net/rest/r/'
  response=$(curl -q -sSL "$pecl_rest$extension"/allreleases.xml)
  pecl_version=$(echo "$response" | grep -m 1 -Eo "(\d*\.\d*\.\d*$stability\d*)")
  if [ ! "$pecl_version" ]; then
    pecl_version=$(echo "$response" | grep -m 1 -Eo "(\d*\.\d*\.\d*)")
  fi
  echo "$pecl_version"
}

# Function to pre-release extensions using PECL
add_unstable_extension() {
  extension=$1
  stability=$2
  prefix=$3
  pecl_version=$(get_pecl_version "$extension" "$stability")
  if ! php -m | grep -i -q -w "$extension" && [ -e "$ext_dir/$extension.so" ]; then
    extension_version=$(php -d="$prefix=$extension" -r "echo phpversion('$extension');")
    if [ "$extension_version" = "$pecl_version" ]; then
      echo "$prefix=$extension" >>"$ini_file" && add_log "$tick" "$extension" "Enabled"
    else
      remove_extension "$extension"
      add_extension "$extension" "sudo pecl install -f $extension-$pecl_version" "$prefix"
    fi
  elif php -m | grep -i -q -w "$extension"; then
    extension_version=$(php -r "echo phpversion('$extension');")
    if [ "$extension_version" = "$pecl_version" ]; then
      add_log "$tick" "$extension" "Enabled"
    else
      remove_extension "$extension"
      add_extension "$extension" "sudo pecl install -f $extension-$pecl_version" "$prefix"
    fi
  else
    add_extension "$extension" "sudo pecl install -f $extension-$pecl_version" "$prefix"
  fi
}

# Function to setup a remote tool
add_tool() {
  url=$1
  tool=$2
  if [ "$tool" = "composer" ]; then
    brew install composer 
    composer -q global config process-timeout 0
    add_log "$tick" "$tool" "Added"
  else
    tool_path=/usr/local/bin/"$tool"
    if [ ! -e "$tool_path" ]; then
      rm -rf "$tool_path"
    fi

    status_code=$(sudo curl -s -w "%{http_code}" -o "$tool_path" -L "$url")
    if [ "$status_code" = "200" ]; then
      sudo chmod a+x "$tool_path"
      if [ "$tool" = "phive" ]; then
        add_extension curl 
        add_extension mbstring 
        add_extension xml 
      elif [ "$tool" = "cs2pr" ]; then
        sudo sed -i '' 's/exit(9)/exit(0)/' "$tool_path"
        tr -d '\r' < "$tool_path" | sudo tee "$tool_path" 
      fi
      add_log "$tick" "$tool" "Added"
    else
      add_log "$cross" "$tool" "Could not setup $tool"
    fi
  fi
}

# Function to add a tool using composer
add_composer_tool() {
  tool=$1
  release=$2
  prefix=$3
  (
    composer global require "$prefix$release"  &&
    sudo ln -sf "$(composer -q global config home)"/vendor/bin/"$tool" /usr/local/bin/"$tool" &&
    add_log "$tick" "$tool" "Added"
  ) || add_log "$cross" "$tool" "Could not setup $tool"
}

# Function to configure PECL
configure_pecl() {
  for tool in pear pecl; do
    sudo "$tool" config-set php_ini "$ini_file" 
    sudo "$tool" config-set auto_discover 1 
    sudo "$tool" channel-update "$tool".php.net 
  done
}

# Function to log PECL, it is installed along with PHP
add_pecl() {
  add_log "$tick" "PECL" "Added"
}

# Function to setup PHP and composer
setup_php_and_composer() {
  export HOMEBREW_NO_INSTALL_CLEANUP=TRUE
  brew tap shivammathur/homebrew-php 
  brew install shivammathur/php/php@"$version" 
  brew link --force --overwrite php@"$version" 
}

# Variables
tick="✓"
cross="✗"
version=$1

# Setup PHP and composer
step_log "Setup PHP"
setup_php_and_composer
ini_file=$(php -d "date.timezone=UTC" --ini | grep "Loaded Configuration" | sed -e "s|.*:s*||" | sed "s/ //g")
echo "date.timezone=UTC" >>"$ini_file"
ext_dir=$(php -i | grep "extension_dir => /usr" | sed -e "s|.*=> s*||")
sudo chmod 777 "$ini_file"
mkdir -p "$(pecl config-get ext_dir)"
semver=$(php -v | head -n 1 | cut -f 2 -d ' ')
add_log "$tick" "PHP" "Installed PHP $semver"
configure_pecl
