- [English](https://github.com/skanmera/ExcelDiff/blob/master/README.md)
- [���{��](https://github.com/skanmera/ExcelDiff/blob/master/README.jp.md)


![](https://github.com/skanmera/ExcelDiff/blob/media/media/logo.png)

### �G�N�Z����GUI�����c�[��

![Demo](https://github.com/skanmera/ExcelDiff/blob/media/media/demo.gif)

![](https://github.com/skanmera/ExcelDiff/blob/media/media/cell_diff.png)

## ���

ExcelDiff �̓G�N�Z����CSV�t�@�C���̍�����O���t�B�J���ɕ\�����邽�߂̃c�[���ł��B
���݂͍����\���ɂ����Ή����Ă��܂��񂪁A�}�[�W�@�\��������邱�Ƃ�ڕW�Ƃ��Ă��܂��B

## �V�X�e���v��

- Windows 7 �ȍ~

## �Ώۃt�@�C��

- .xls
- .xlsx
- .csv
- .tsv

## �C���X�g�[��

[����](https://github.com/skanmera/ExcelDiff/releases/)���� ExcelDiffSetup.msi��_�E�����[�h���Ď��s���ĉ������B

## �g����

### �V���[�g�J�b�g����N��

![](https://github.com/skanmera/ExcelDiff/blob/media/media/shortcut.png)

### �G�N�X�v���[���[�̃R���e�L�X�g���j���[����N��

![](https://github.com/skanmera/ExcelDiff/blob/media/media/context.png)

### �R�}���h���C������N��

```
ExcelDiff.GUI diff [�I�v�V����]
```

|�I�v�V����|���|�^|�f�t�H���g�l|
|------|-----------|----|-------|
|```-s``` ```--src-path```|�����̃t�@�C���p�X|string|
|```-d``` ```--dst-path``` |�E���̃t�@�C���p�X| string
|```-c``` ```--external-cmd```|�Ώۃt�@�C���ȊO�̍�����\���������Ƃ��Ɏg�p����O���R�}���h��w�肵�܂�| string
|```-i``` ```--immediately-execute-external-cmd```|�G���[�����������Ƃ��Ƀ_�C�A���O��\�������ɊO���R�}���h����s���܂�| bool | false
|```-w``` ```--wait-external-cmd```|�O���R�}���h�̊�����ҋ@���܂�|bool|false
|```-v``` ```--validate-extension```|�Ώۃt�@�C�����ǂ����̌��؂�s���܂��Bfalse�̏ꍇ�A�ΏۊO�t�@�C���ł�I�[�v������݂܂�|bool|false
|```-e``` ```--empty-file-name```|��̃t�@�C������w�肵�܂��B|string
|```-k``` ```--keep-file-history```|�ŋߎg�p�����t�@�C���ɒǉ����܂���|bool|false

### Git��diff�c�[���Ƃ��ċN��

.gitconfig
```
[diff]
tool = ExcelDiff

[difftool "ExcelDiff"]
cmd = \"D:/Program Files/ExcelDiff/ExcelDiff.GUI.exe\" diff -s \"$LOCAL\" -d \"$REMOTE\" -c WinMerge -i -w -v -k 

[alias]
windiff = difftool -g -y -t ExcelDiff
```

### Mercurial��diff�c�[���Ƃ��ċN��

mercurial.ini
```
[merge-tools]
exceldiff.executable = D:\Program Files\ExcelDiff\ExcelDiff.GUI.exe
exceldiff.diffargs = diff -s $parent1 -d $child -c WinMerge -i -w -v -e empty -k

[tortoisehg]
vdiff = exceldiff
```

## �O���R�}���h�̓o�^
�R�}���h���C���̃I�v�V����"--external-cmd"�Ŏw�肵�����O�̊O���R�}���h��ǉ����܂��B

![](https://github.com/skanmera/ExcelDiff/blob/media/media/ext_cmd_win.png)

### ���p�\�ȕϐ�
|�ϐ�|���|
|------|----------|
|```${SRC}```|�E���̃t�@�C���p�X|
|```${DST}```|�����̃t�@�C���p�X|  
  
  
�R�}���h���C������̎w�肾���łȂ��A�c�[��������O���R�}���h����s�ł��܂��B

![](https://github.com/skanmera/ExcelDiff/blob/media/media/ext_cmd.png)

## �t�@�C�����̐ݒ�

�t�@�C�����ɍs�w�b�_�A��w�b�_�Ȃǂ�ݒ�ł��܂��B

![](https://github.com/skanmera/ExcelDiff/blob/media/media/file_settings.png)

## �F�̐ݒ�

�w�i�F��J�X�^�}�C�Y�ł��܂��B

![](https://github.com/skanmera/ExcelDiff/blob/media/media/settings.png)

## �V���[�g�J�b�g�L�[

|Shortcut Key|Description|
|---|-----------|
|Ctrl + ��|���̕ύX���ꂽ�Z���Ɉړ�|
|Ctrl + ��|�O�̕ύX���ꂽ�Z���Ɉړ�|
|Ctrl + ��|���̕ύX���ꂽ�s�Ɉړ�|
|Ctrl + ��|�O�̕ύX���ꂽ�s�Ɉړ�|
|Ctrl + K|���̒ǉ����ꂽ�s�Ɉړ�|
|Ctrl + I|�O�̒ǉ����ꂽ�s�Ɉړ�|
|Ctrl + L|���̍폜���ꂽ�s�Ɉړ�|
|Ctrl + O|�O�̍폜���ꂽ�s�Ɉړ�|
|Ctrl + F|�Z�������|
|F9|���̌������ʂɈ�v����Z���Ɉړ�|
|F8|�O�̌������ʂɈ�v����Z���Ɉړ�|
|Ctrl + C|�I������Z����^�u��؂�ŃR�s�[(�G�N�Z���ւ̓\��t��)|
|Ctrl + Shift + C|�I������Z����J���}��؂�ŃR�s�[|
|Ctrl + D|�R���\�[����\��(�B��)|
|Ctrl + B|�I��͈͂̍�������O�Ƃ��ďo��|

## �ύX����O�Ƃ��ďo�͂���

Ctrl+D�@������̓R���e�L�X�g���j���[����u���O��o�́v��I����邱�ƂŁA�ύX�_����O�Ƃ��ďo�͂��܂��B
�t�H�[�}�b�g�́u�������o�ݒ�v����ύX�\�ł��B

![](https://github.com/skanmera/ExcelDiff/blob/media/media/log.png)


## ���m�̖��_

- <h4>��̒ǉ���폜������ꍇ�ɁA���̈ʒu�����҂��Ă���ʒu�ɕ\������Ȃ����Ƃ�����.</h4>
���̖��͓K�؂ȃw�b�_��w�肵�č����𒊏o���Ȃ������Ƃŉ�����邱�Ƃ�����܂��B
��̓I�ɂ͈ȉ��̎菇��s���Ă��������B

1. �K�؂ȃw�b�_�̃Z����I�����
2. �E�N���b�N�ŃR���e�L�X�g���j���[��\������
3. "���̍s��w�b�_�Ƃ��č����𒊏o����"��I��


## ���C�Z���X

#### MIT Licence

Copyright (c)2017 skanmera

�ȉ��ɒ�߂����ɏ]���A�{�\�t�g�E�F�A����ъ֘A�����̃t�@�C���i�ȉ��u�\�t�g�E�F�A�v�j�̕�����擾���邷�ׂĂ̐l�ɑ΂��A�\�t�g�E�F�A�𖳐����Ɉ������Ƃ𖳏��ŋ����܂��B����ɂ́A�\�t�g�E�F�A�̕�����g�p�A���ʁA�ύX�A�����A�f�ځA�Еz�A�T�u���C�Z���X�A�����/�܂��͔̔����錠���A����у\�t�g�E�F�A��񋟂��鑊��ɓ������Ƃ�����錠����������Ɋ܂܂�܂��B

��L�̒��쌠�\������і{�����\����A�\�t�g�E�F�A�̂��ׂĂ̕����܂��͏d�v�ȕ����ɋL�ڂ����̂Ƃ��܂��B

�\�t�g�E�F�A�́u����̂܂܁v�ŁA�����ł��邩�Öقł��邩���킸�A����̕ۏ؂�Ȃ��񋟂���܂��B�����ł����ۏ؂Ƃ́A���i���A����̖ړI�ւ̓K�����A����ь�����N�Q�ɂ��Ă̕ۏ؂�܂݂܂����A����Ɍ��肳����̂ł͂���܂���B ��҂܂��͒��쌠�҂́A�_��s�ׁA�s�@�s�ׁA�܂��͂���ȊO�ł��낤�ƁA�\�t�g�E�F�A�ɋN���܂��͊֘A���A���邢�̓\�t�g�E�F�A�̎g�p�܂��͂��̑��̈����ɂ���Đ������؂̐����A���Q�A���̑��̋`���ɂ��ĉ���̐ӔC�����Ȃ���̂Ƃ��܂��B
