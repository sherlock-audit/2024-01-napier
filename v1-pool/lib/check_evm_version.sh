#!/bin/bash

if forge_config=$(forge config); then
    if echo "$forge_config" | grep -q 'evm_version = "shanghai"'; then
        echo -n 0x00
    else
        echo -n 0x01
    fi
else
    echo "Error running 'forge config'."
    echo -n 0x01
fi
