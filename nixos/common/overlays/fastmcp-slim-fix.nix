final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pyFinal: pyPrev: {
      fastmcp-slim = pyPrev.fastmcp-slim.overridePythonAttrs (old: {
        sourceRoot = "${old.src.name}";
      });
    })
  ];
}
