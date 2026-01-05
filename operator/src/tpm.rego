package policy

import rego.v1

default hardware := 2

default configuration := 2

default executables := 33

## TPM validation
executables := 3 if {
	lower(input.tpm.pcrs[4]) in data.reference.tpm_pcr4
	lower(input.tpm.pcrs[14]) in data.reference.tpm_pcr14
}

# Azure SNP vTPM validation
executables := 3 if {
	lower(input.azsnpvtpm.tpm.pcr04) in data.reference.tpm_pcr4
	lower(input.azsnpvtpm.tpm.pcr14) in data.reference.tpm_pcr14
}

hardware := 2 if tpm_pcrs_valid
executables := 3 if tpm_pcrs_valid
configuration := 2 if tpm_pcrs_valid

default file_system := 0
default instance_identity := 0
default runtime_opaque := 0
default storage_opaque := 0
default sourced_data := 0
result := {
  "executables": executables,
  "hardware": hardware,
  "configuration": configuration,
  "file-system": file_system,
  "instance-identity": instance_identity,
  "runtime-opaque": runtime_opaque,
  "storage-opaque": storage_opaque,
  "sourced-data": sourced_data,
}
