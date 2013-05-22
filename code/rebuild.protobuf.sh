#! /bin/bash
protoc ./R/src/RMRHeader.proto --cpp_out=. --java_out=./java
protoc ./R/src/rexp.proto --cpp_out=. --java_out=./java
