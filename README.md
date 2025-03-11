# Installation Instructions

Follow these steps to set up and run the "escape" project:

## 1. Download the init script
Create a dedicated folder (eg. "escape") and copy the init.sh file in it:
```sh
mkdir escape && cd escape
curl -SL https://github.com/XXX -o init.sh
```

## 2. Launch the bash script
Ensure the `init.sh` script is executable and then run it:
```sh
chmod +x init.sh && ./init.sh
```

## 3. Navigate on the application with your browser
Retrieve the IP of the docker container (last line in your terminal) and navigate to it
```
http://172.17.0.2/index.php
```

# Goal
Your goal is to read the generated ```flag.txt``` file (that is on your host file system in the "escape" folder) from the docker container created.
