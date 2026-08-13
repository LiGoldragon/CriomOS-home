{
  outputs = _: {
    system = throw ''
      CriomOS-home: no system input was provided.

      The OS-owned deployment path must provide the target system and
      projected horizon by overriding this input.
    '';
  };
}
