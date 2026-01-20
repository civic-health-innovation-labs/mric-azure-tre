# Airlock Troubleshooting

## Users cannot create Review VMs

If a user sees an error when creating Review VMs, this most likely means that the configuration isn't correct.
Double-check that all GUIDs don't have any symbols missing, and the names of templates are correct.

[![Review VM Error](../assets/using-review-vm-errors.png)](../assets/using-review-vm-errors.png)


## Files do not appear in Review Data folder on the VM

If the Review Data folder is empty, it's likely because the review VM can't connect to the storage account. Import requests must be reviewed using a VM inside the workspace, and export requests must be reviewed using a VM outside the workspace.

For imports ensure that the `airlock-import-review` workspace template is being used and configured in the airlock configuration for the workspace.


## Airlock request does not move through the workflow as expected

If the Airlock request does not move through the workflow as expected, it's likely an issue with the Azure Function that processes airlock requests. This function is deployed as part of the TRE, and can be found in the Azure Portal under the name `func-airlock-processor-<tre_id>`.

To troubleshoot, view the function invocations starting with the StatusChangedQueue Trigger, then the other functions as shown in the image below:

[![Function details](../assets/airlock_functions.png)](../assets/airlock_functions.png)

Look for errors in the function invocations in the same time frame that the airlock request was created. Even if the function executed successfully, there may still be errors within the function invocation details. Invocations that take longer can also be a sign of an issue. For example:

[![Functions error](../assets/airlock_functions_error.png)](../assets/airlock_functions_error.png)

If this error should have been handled please create an issue on the GitHub repository for the Azure TRE.

## Python 3.12 `distutils` missing in Airlock Processor

**Symptom**: Function app errors with `ModuleNotFoundError: No module named 'distutils'` when importing `strtobool` in `BlobCreatedTrigger` or `ScanResultTrigger` after moving to Python 3.12.

**Root cause**: `distutils` was removed from the Python 3.12 standard library, so `from distutils.util import strtobool` fails on the Functions worker runtime.

**Fix applied**:
- Replaced the `distutils` import with a small local `strtobool` helper in both triggers: [airlock_processor/BlobCreatedTrigger/__init__.py](../../airlock_processor/BlobCreatedTrigger/__init__.py#L1-L34) and [airlock_processor/ScanResultTrigger/__init__.py](../../airlock_processor/ScanResultTrigger/__init__.py#L1-L32).
- Rebuilt and pushed the container image via `make build-and-push-airlock-processor`, then restarted the function app to pull the new image.

**Verification steps**:
1. Confirm the function app setting `DOCKER_CUSTOM_IMAGE_NAME` points to the updated tag (e.g. `airlock-processor:0.8.0`).
2. Tail logs after restart to ensure triggers start cleanly:
	```bash
	az functionapp log tail --name func-airlock-processor-<tre_id> --resource-group rg-<tre_id>
	```
3. Ensure `ENABLE_MALWARE_SCANNING` is set to a valid truthy/falsey string (`true/false`, `1/0`, `yes/no`).

**If you hit it again**: cherry-pick or re-apply the above change set, rebuild/push the image, and restart the function app.
