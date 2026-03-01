set dotenv-load := true

just := `which just`
mkosi := `which mkosi`

default:
    {{just}} --list --unsorted

clean:
    sudo PATH="$PATH" {{just}} _clean

sysexts:
    sudo PATH="$PATH" {{just}} _sysexts

snow:
    sudo PATH="$PATH" {{just}} _snow

snowloaded:
    sudo PATH="$PATH" {{just}} _snowloaded

snowfield:
    sudo PATH="$PATH" {{just}} _snowfield

snowfieldloaded:
    sudo PATH="$PATH" {{just}} _snowfieldloaded

cayo:
    sudo PATH="$PATH" {{just}} _cayo

cayoloaded:
    sudo PATH="$PATH" {{just}} _cayoloaded

test-install image="output/snow":
    sudo PATH="$PATH" {{just}} _test-install {{image}}

run-qemu image="output/snow":
    sudo PATH="$PATH" DISK_SIZE=50G {{just}} _run-qemu {{image}}

# Private targets (run as root via sudo)

[private]
_clean:
    {{mkosi}} clean -ff

[private]
_sysexts: _clean
    {{mkosi}} build

[private]
_snow: _clean
    {{mkosi}} --profile snow build

[private]
_snowloaded: _clean
    {{mkosi}} --profile snowloaded build

[private]
_snowfield: _clean
    {{mkosi}} --profile snowfield build

[private]
_snowfieldloaded: _clean
    {{mkosi}} --profile snowfieldloaded build

[private]
_cayo: _clean
    {{mkosi}} --profile cayo build

[private]
_cayoloaded: _clean
    {{mkosi}} --profile cayoloaded build

[private]
_test-install image="output/snow":
    ./test/bootc-install-test.sh {{image}}

[private]
_run-qemu image="output/snow":
    ./test/run-qemu.sh {{image}}
