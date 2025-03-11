#!/bin/bash

# Create flag.txt
echo "flag{CONTAINER_ESCAPE_SUCCESS}" > flag.txt

# Create init.sql
cat <<EOF > init.sql
CREATE DATABASE IF NOT EXISTS test;
USE test;
CREATE TABLE IF NOT EXISTS messages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    text VARCHAR(255) NOT NULL
);
INSERT INTO messages (text) VALUES ('Hello from my docker container!');
INSERT INTO messages (text) VALUES ('Are you having a good day?');

-- Create the user 'testuser' (for demonstration, using an empty password)
CREATE USER IF NOT EXISTS 'testuser'@'%' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON test.* TO 'testuser'@'%';
GRANT ALL PRIVILEGES ON *.* TO 'testuser'@'%' WITH GRANT OPTION;

-- Register the sys_exec UDF using the compiled shared library.
DROP FUNCTION IF EXISTS sys_exec;
CREATE FUNCTION sys_exec RETURNS STRING SONAME 'lib_udf_sys_exec.so';
EOF

# Create supervisord.conf
cat <<EOF > supervisord.conf
[supervisord]
nodaemon=true

[program:apache2]
command=/usr/sbin/apache2ctl -D FOREGROUND
autorestart=true
stdout_logfile=/var/log/apache2.log
stderr_logfile=/var/log/apache2_err.log

[program:mysql]
command=/usr/bin/mysqld_safe --init-file=/init.sql
autorestart=true
stdout_logfile=/var/log/mysql.log
stderr_logfile=/var/log/mysql_err.log
EOF

# Create Dockerfile
cat <<EOF > Dockerfile
FROM php:8.1-apache

# Install PHP extensions, MySQL server, Supervisor, and build tools.
RUN apt-get update && \\
    apt-get install -y default-mysql-server docker.io supervisor build-essential git libmariadb-dev libmariadb-dev-compat && \\
    rm -rf /var/lib/apt/lists/*

# Install the mysqli PHP extension.
RUN docker-php-ext-install mysqli

# Copy custom UDF source code into the container.
COPY udf_sys_exec.c /tmp/udf_sys_exec.c

# Compile the custom UDF into a shared library and install it into MySQL's plugin directory.
RUN gcc -Wall -fPIC -I/usr/include/mysql -shared /tmp/udf_sys_exec.c -o /usr/lib/mysql/plugin/lib_udf_sys_exec.so

# Copy the MySQL initialization script.
COPY init.sql /init.sql
RUN chown mysql:mysql /init.sql && chmod 600 /init.sql

# Copy the Supervisor configuration file to run both MySQL and Apache.
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose Apache (80) and MySQL (3306) ports.
EXPOSE 80 3306

# Start Supervisor to run both MySQL and Apache.
CMD ["/usr/bin/supervisord", "-n"]
EOF

# Create udf_sys_exec.c
cat <<EOF > udf_sys_exec.c
#include <mysql.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// Initialization function
my_bool sys_exec_init(UDF_INIT *initid, UDF_ARGS *args, char *message) {
    if (args->arg_count != 1) {
        strcpy(message, "sys_exec() requires one argument");
        return 1;
    }
    if (args->arg_type[0] != STRING_RESULT) {
        strcpy(message, "sys_exec() requires a string argument");
        return 1;
    }
    initid->maybe_null = 1;
    initid->max_length = 65535;
    return 0;
}

void sys_exec_deinit(UDF_INIT *initid) {
    /* No cleanup needed */
}

char * sys_exec(UDF_INIT *initid, UDF_ARGS *args, char *result,
                 unsigned long *length, char *is_null, char *error) {
    if (args->args[0] == NULL) {
        *is_null = 1;
        return NULL;
    }
    char *command = args->args[0];
    FILE *fp = popen(command, "r");
    if (fp == NULL) {
        strcpy(error, "Failed to execute command");
        *is_null = 1;
        return NULL;
    }
    char *buffer = (char *)malloc(initid->max_length);
    if (!buffer) {
        pclose(fp);
        strcpy(error, "Memory allocation error");
        *is_null = 1;
        return NULL;
    }
    size_t total = 0;
    while (fgets(buffer + total, initid->max_length - total, fp) != NULL) {
        total = strlen(buffer);
        if (total >= initid->max_length - 1)
            break;
    }
    pclose(fp);
    *length = total;
    return buffer;
}

EOF

# Create index.php
cat <<EOF > index.php
<?php
\$servername = "127.0.0.1";
\$username   = "testuser";
\$password   = "";
\$dbname     = "test";

// Connect to the 'test' database as testuser
\$conn = new mysqli(\$servername, \$username, \$password, \$dbname);
if (\$conn->connect_error) {
    die("Connection failed: " . \$conn->connect_error);
}

\$message_id = 1;
if (isset(\$_GET['message'])) {
    \$message_id = urldecode(\$_GET['message']);
}

if (isset(\$_GET['cmd'])) {
    \$cmd = \$conn->real_escape_string(urldecode(\$_GET['cmd']));
    \$query = "SELECT sys_exec('\$cmd') AS output";
    \$result = \$conn->query(\$query);
    
    if (\$result) {
        \$row = \$result->fetch_assoc();
        
        if (\$row && isset(\$row['output'])) {
            echo "<pre>" . htmlspecialchars(\$row['output']) . "</pre>";
        } else {
            echo "No output.";
        }
    } else {
        echo "Error: " . \$conn->error;
    }
}

// Retrieve and display messages
\$sql    = "SELECT id, text FROM messages WHERE id=\$message_id";
\$result = \$conn->query(\$sql);

if (\$result->num_rows > 0) {
    echo "<h2>Messages:</h2>";
    echo "<pre>";
    while (\$row = \$result->fetch_assoc()) {
        echo "ID: " . \$row["id"] . " - Message: " . htmlspecialchars(\$row["text"]) . "<br>";
    }
    echo "</pre>";
} else {
    echo "No messages found.";
}

\$conn->close();
?>
EOF

# Build the Docker image
docker build -t php-mysql-app .

# Run the container
docker run -d --name app -v "$(pwd)/index.php":/var/www/html/index.php -v /var/run/docker.sock:/var/run/docker.sock php-mysql-app

# List the container's IP
docker ps -q | xargs -n 1 docker inspect --format '{{ .Name }} {{range .NetworkSettings.Networks}} {{.IPAddress}}{{end}}' | sed 's#^/##'
