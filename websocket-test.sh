#!/bin/bash

url="http://VPMWS-1401950825.us-east-2.elb.amazonaws.com/socket.io/?EIO=4&transport=websocket"
port="80"

token="AtwtVkfWzSpO0HUjp+mpVQ=="

curl --include \
     --no-buffer \
     --header "Connection: Upgrade" \
     --header "Upgrade: websocket" \
     --header "Host: staging.ws.vpmsolutions.com" \
     --header "Origin: https://staging.app.vpmsolutions.com" \
     --header "Sec-WebSocket-Key: $token" \
     --header "Sec-WebSocket-Version: 13" \
     $url
