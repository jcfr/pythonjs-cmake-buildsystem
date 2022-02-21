pythonjs-cmake-buildsystem
--------------------------

Archive of an experiment done in April 2016 to build Python 2.7 using [python-cmake-buildsystem][] to support use in a web environment.

```
cmake \
  -DPYTHON_CMAKE_BUILDSYSTEM_DIR:PATH=/path/to/src/python-cmake-buildsystem \
  -DPYTHON_VERSION:STRING=2.7.11 \
  -P PythonJs.cmake
```

[python-cmake-buildsystem]: https://github.com/python-cmake-buildsystem/python-cmake-buildsystem

## License

This software is licensed under the terms of the [Apache Licence Version 2.0](LICENSE_Apache_20).
