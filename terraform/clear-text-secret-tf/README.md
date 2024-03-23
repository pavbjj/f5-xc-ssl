# Usage
## Copy your XC .p12 file to relevant location and fill variables.tf

## base64 your keys

```
cat cert.pem | base64
```

Paste base64 to main.tf prefixed by "string:///"
