{ pkgs }:

let
  ps = pkgs.python3Packages;

  mozterm = ps.buildPythonPackage {
    pname = "mozterm"; version = "1.0.0"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/ab/eb/0c53684f5821d666372c6ea03d8c64558c8f74fda0fd5b24ae3dd2ab6a95/mozterm-1.0.0-py2.py3-none-any.whl";
      hash = "sha256-9er6JcI9OR4qK7HdRe6Sj8njyBGXejhWtaWgd4ARBTw=";
    };
    propagatedBuildInputs = [ ps.six ];
    doCheck = false;
  };

  mozsystemmonitor = ps.buildPythonPackage {
    pname = "mozsystemmonitor"; version = "1.0.1"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/95/59/7a5f8f48946281c7a24bcecd722925493c0e67dabbc0826d215f2f45da9c/mozsystemmonitor-1.0.1-py2.py3-none-any.whl";
      hash = "sha256-qzCnWH/f7mBBKH97lTkRsH0EQdIr+gS7TYJUHEi9ywI=";
    };
    propagatedBuildInputs = [ ps.psutil ];
    doCheck = false;
  };

  mozfile = ps.buildPythonPackage {
    pname = "mozfile"; version = "3.0.0"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/76/cd/fe6b0afa57fbf026631de1435682735dae0aa0ffbe3855f62806da31c55b/mozfile-3.0.0-py2.py3-none-any.whl";
      hash = "sha256-Owr82i+ouALvZX34ClbyFhkAj2H8wUt1YSQCjXt631w=";
    };
    propagatedBuildInputs = [ ps.six ];
    doCheck = false;
  };

  mozlog = ps.buildPythonPackage {
    pname = "mozlog"; version = "8.1.0"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/d5/d0/2b4570c6328aefe8060f950577ff660bac1b4e57e9ba9821977c06f03f43/mozlog-8.1.0-py2.py3-none-any.whl";
      hash = "sha256-vEpxXgOJbr23J9TfEz0YjLU7zOGKG7uQuqa7prg7AHo=";
    };
    propagatedBuildInputs = [ ps.blessed mozfile mozsystemmonitor mozterm ];
    doCheck = false;
  };

  mozinfo = ps.buildPythonPackage {
    pname = "mozinfo"; version = "1.2.3"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/28/b2/0efcb9aa6d1362aa00b567c8f355f028332a5a533f80c45e5dacd12a5466/mozinfo-1.2.3-py2.py3-none-any.whl";
      hash = "sha256-kODPs3f8LMP60CPTjB9tYKkTVAD/VoSgSr95ylzDxSE=";
    };
    propagatedBuildInputs = [ ps.distro mozfile ];
    doCheck = false;
  };

  mozdevice = ps.buildPythonPackage {
    pname = "mozdevice"; version = "4.2.0"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/90/3c/02d47e719505af2745df5c0d5083305850ccd02fc56cbee4c4eca8fa321f/mozdevice-4.2.0-py2.py3-none-any.whl";
      hash = "sha256-f7uWHNqVGywt1KvC6K73Pf2Zqg/9hS2nB/m2Ma12Bkc=";
    };
    propagatedBuildInputs = [ mozlog ];
    doCheck = false;
  };

  mozprocess = ps.buildPythonPackage {
    pname = "mozprocess"; version = "1.4.0"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/7c/a3/354e9f0c8b629319e6f6334beaf42e38eeb5ddc821c77e9082752b037d3f/mozprocess-1.4.0-py2.py3-none-any.whl";
      hash = "sha256-mjshjasPEncnW+fYnWc81VsGJRkEOoihoad+rO/f314=";
    };
    propagatedBuildInputs = [ mozinfo ];
    doCheck = false;
  };

  mozprofile = ps.buildPythonPackage {
    pname = "mozprofile"; version = "3.0.0"; format = "setuptools";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/00/eb/9de383c0ccfa3ac7ca21fe5d8fd861579c83c119d72ae1fe2d25e787c5b3/mozprofile-3.0.0.tar.gz";
      hash = "sha256-r2YSkMyRsVtqaUPSv1orD3CLyeAomo4L8dp1k+qqttA=";
    };
    propagatedBuildInputs = [ mozfile mozlog ps.six ];
    doCheck = false;
  };

  mozrunner = ps.buildPythonPackage {
    pname = "mozrunner"; version = "8.4.0"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/68/3a/2953c91c54a4e4e63658f239eec31cd7a2820870fb80ddbb7bf3f15ef1ac/mozrunner-8.4.0-py2.py3-none-any.whl";
      hash = "sha256-+l/G7fxQHr8t0PrySTSmJuLg9nq7JtSHhlH+pUJ1sU8=";
    };
    propagatedBuildInputs = [ mozdevice mozfile mozinfo mozlog mozprocess mozprofile ];
    doCheck = false;
  };

  mozversion = ps.buildPythonPackage {
    pname = "mozversion"; version = "2.4.0"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/db/86/7ec5f7c4edee8929523dc9c07d1aba4a89d8f53a99b0fcaa3d71c71f99cc/mozversion-2.4.0-py2.py3-none-any.whl";
      hash = "sha256-2aC5l/9IqXn2lK+eb9P7gZ9BHoGZBFoLNi1roRLLVnY=";
    };
    propagatedBuildInputs = [ mozlog ps.six ];
    doCheck = false;
  };

  marionetteDriver = ps.buildPythonPackage {
    pname = "marionette-driver"; version = "3.6.0"; format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/82/d4/a97dc9cf26986d53b25cf073d522aa3f97a72b45c34ade009988ac79c4c3/marionette_driver-3.6.0-py3-none-any.whl";
      hash = "sha256-UClWjlBSIPwrXnPi5H7RD5Ydlp0VFwOK6muQLvv7oDQ=";
    };
    propagatedBuildInputs = [ mozrunner mozversion ];
    doCheck = false;
  };

in pkgs.python3.withPackages (p: [
  p.python-telegram-bot
  p.python-dotenv
  p.pexpect
  p.httpx
  p.ddgs
  p.beautifulsoup4
  p.lxml
  marionetteDriver
])
