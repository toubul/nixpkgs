{
  lib,
  buildPythonPackage,
  django,
  fetchPypi,
  pytest-django,
  pytestCheckHook,
  pythonOlder,
}:

buildPythonPackage rec {
  pname = "django-treebeard";
  version = "4.7.1";
  format = "setuptools";

  disabled = pythonOlder "3.8";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-hG5GKQS0NxVfduBJB7pOSEgHFoVfiLiY30Eivc+9bpg=";
  };

  propagatedBuildInputs = [ django ];

  nativeCheckInputs = [
    pytest-django
    pytestCheckHook
  ];

  pythonImportsCheck = [ "treebeard" ];

  meta = with lib; {
    description = "Efficient tree implementations for Django";
    homepage = "https://tabo.pe/projects/django-treebeard/";
    changelog = "https://github.com/django-treebeard/django-treebeard/blob/${version}/CHANGES.md";
    license = licenses.asl20;
  };
}
