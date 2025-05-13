# MQTT User Creation Script

Run the script using ```curl -s -o mqtt_user_management_tool.sh https://raw.githubusercontent.com/VaeluxV/MQTT-User-creation-script/main/mqtt_user_management_tool.sh && sudo bash mqtt_user_management_tool.sh && rm mqtt_user_management_tool.sh```

This will get the latest version of the script from the repo, run it, then once done, it will auto remove itself.

---

You can also download manually, then run this script standalone.

The config must contain both the anonymous auth setting as well as the password file location. I might add more options for this later.

---

> Tested on ubuntu server 24.04 LTS with Mosquitto only. I cannot guarantee this will work on other systems.

Open for everyone to use, edit and redistribute. Licensed under the 'Unlicense' license. In other words, this script is considered public domain.

~ Valerie