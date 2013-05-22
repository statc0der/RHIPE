#! /bin/bash
cd R/src
protoc RMRHeader.proto --cpp_out=. --java_out=../../java
protoc rexp.proto --cpp_out=. --java_out=../../java
