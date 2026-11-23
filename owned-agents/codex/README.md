# Managed Codex package

The canonical package uses the exact official complete stable package
from the checked release manifest. The plain, stable, next and candidate
profiles share that package. Each remains a distinct runtime with its own
configuration, session home and, where configured, app-server endpoint.
Refresh the manifest with the package updater and run the release, app-server,
and Herdr gates before switching profiles.
