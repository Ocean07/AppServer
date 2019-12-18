# AppServer

1. 安装Jenkins
   1> 安装Java环境，下载java8的jdk安装
   2>使用brew install jenkins-lts, 千万不要下载安装包安装（有坑，权限问题等）。安装jenkins插件
  3>Jenkins 打包配置，生成ipa包

2. 搭建OTA服务
  1> 写ota服务器，实现静态资源下载，动态生成安装ipa需要的文件
  2> 安装Nginx, brew install nginx (参考: )
  3> 使用ssl自签证书实现https访问，使用nginx代理（参考：https://www.liaoxuefeng.com/article/990311924891552）

注意点：
 安装jenkins时，使用brew安装，不要下载安装包
 生成ssl自签证书时，CN项一定要填写对应的域名，不然验证不通过

3. 使用。https://www.jianshu.com/p/d312ac54c730
   首次安装app需要先安装并信任网站证书
