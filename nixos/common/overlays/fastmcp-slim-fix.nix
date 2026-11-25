_final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_pyFinal: pyPrev: {
      fastmcp-slim = pyPrev.fastmcp-slim.overridePythonAttrs (old: {
        sourceRoot = "${old.src.name}";
      });
    })
  ];
}
