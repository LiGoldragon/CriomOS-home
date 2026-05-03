{
  outputs = _: {
    system = throw ''
      CriomOS-home: no system input was provided.

      Home-only deployment is driven by lojix, which derives the target
      system from the projected horizon and overrides this input.
    '';
  };
}
