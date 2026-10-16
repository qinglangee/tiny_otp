import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('帮助与使用说明')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: const [
            Text(
              '踢你OTP（TinyOTP）是一个离线优先的动态验证码应用。它在本机保存兼容 TOTP 标准的验证器密钥，并按时间生成一次性验证码。添加账号、查看验证码和搜索账号不需要网络连接。',
            ),
            SizedBox(height: 12),
            Text(
              '账号数据保存在本机的加密存储中。备份使用独立密码加密。请妥善保管备份密码，忘记后无法从备份文件中恢复账号。',
            ),
            SizedBox(height: 20),
            _HelpSection(
              title: '添加账号：扫描二维码',
              paragraphs: [
                '1. 在要启用双重验证的网站或服务中，选择使用验证器应用（Authenticator app），打开设置二维码。',
                '2. 首页点击 Add account，再选择 Scan a setup QR code。',
                '3. 首次扫码时，按系统提示允许相机权限。相机只在扫码页面使用。',
                '4. 将二维码放入扫描框。二维码在本机解析。核对服务名称、账号名称和验证码参数后，点击 Save。',
                '5. 回到服务的双重验证设置页面，输入 TinyOTP 当前显示的验证码，完成绑定。',
                '二维码无法扫描时，可以改用手动输入。如果服务提供恢复码，请另外安全保存；恢复码不是 TOTP 密钥。',
              ],
            ),
            _HelpSection(
              title: '添加账号：手动输入',
              paragraphs: [
                '1. 点击 Add account → Enter details manually。',
                '2. 填写 Issuer / service（服务名称）、Account name（用户名、邮箱或备注）和 Base32 secret（服务提供的验证器密钥）。',
                '3. 按服务提供的信息选择 Algorithm（算法）、Digits（验证码位数）和 Period (seconds)（有效时间步长）。常见默认值为 SHA1、6 位、30 秒；服务提供其他参数时应以服务信息为准。',
                '4. 点击 Review 检查服务名称和账号信息，确认后点击 Save。',
                '密钥是敏感信息，请勿发给他人或粘贴到不受信任的位置。相同服务名称和账号名称不能重复添加。',
              ],
            ),
            _HelpSection(
              title: '查看和使用验证码',
              paragraphs: [
                '账号卡片显示服务名称、账号名称、当前验证码和剩余有效时间。验证码根据系统时间刷新。',
                '点击账号卡片即可复制验证码，复制内容只有验证码；页面会显示 Code copied。',
                '验证码临近过期时，可以等新验证码刷新后再输入。若验证码持续被拒绝，请检查手机是否启用了自动设置日期和时间。',
              ],
            ),
            _HelpSection(
              title: '搜索和排序',
              paragraphs: [
                '在 Search accounts 搜索框输入服务名称或账号名称进行查找；清空搜索框可显示全部账号。',
                '点击 Sort by 右侧选项，可按 Issuer（服务名称）或 Account name（账号名称）排序。',
              ],
            ),
            _HelpSection(
              title: '编辑和删除账号',
              paragraphs: [
                '编辑：点击账号卡片右上角 ⋮，选择 Edit，修改 Issuer / service 或 Account name，然后点击 Save。编辑只修改显示名称，不会更改密钥或算法参数。',
                '删除：点击账号卡片右上角 ⋮，选择 Delete；在确认窗口再次点击 Delete 才会移除，点击 Cancel 则保留。',
                '删除账号不会关闭服务网站上的双重验证。请先确认仍可通过服务提供的其他验证或恢复方式登录。',
              ],
            ),
            _HelpSection(
              title: '创建加密备份',
              paragraphs: [
                '1. 点击首页右上角的加密备份图标，进入 Encrypted backup。',
                '2. 点击 Create encrypted backup，设置并确认至少 12 个字符的独立备份密码。它不同于手机解锁密码。',
                '3. 在系统文件保存窗口选择位置，保存 tinyotp-backup.tinyotp。',
                '4. 安全保存备份文件和密码。忘记密码无法恢复；请勿将文件和密码放在同一个不安全的位置。',
                '备份文件已加密，不是明文密钥导出。应用不会自动上传备份，保存位置由你选择。',
              ],
            ),
            _HelpSection(
              title: '从备份恢复',
              paragraphs: [
                '1. 在新设备打开 Encrypted backup，点击 Restore from backup，并选择 .tinyotp 文件。',
                '2. 输入创建备份时设置的密码。',
                '3. 核对恢复预览中的账号数量。如果本机已有账号，恢复会替换现有账号；确认后点击 Restore，取消则不执行恢复。',
                '4. 恢复后，账号会使用当前设备的本地密钥重新加密保存。确认验证码正常显示，并到对应服务验证。',
                '密码错误、文件损坏或格式不支持时，恢复会停止。确认新设备恢复成功并可正常登录前，请勿删除原设备上的账号。',
              ],
            ),
            _HelpSection(
              title: '当前未提供',
              paragraphs: [
                '当前版本没有应用锁、生物识别、云同步或账号登录功能，也暂不提供深色模式。备份由用户手动保存和恢复。',
              ],
            ),
          ],
        ),
      );
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final paragraph in paragraphs) ...[
              Text(paragraph),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
}
