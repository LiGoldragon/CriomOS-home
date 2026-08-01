## Shared-input pin discipline

When bumping a component pin (lojix, orchestrate, spirit, or any shared input)
in either CriomOS or CriomOS-home, check the other flake's pin for the same
input and bump it to match. The authoritative version is whichever flake was
intentionally updated; the other must follow within the same commit sequence.

Never deploy via home-manager switch without first verifying that CriomOS-home's
standalone pins match CriomOS's current pins for all shared inputs.
