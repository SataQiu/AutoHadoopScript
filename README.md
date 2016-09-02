## AutoHadoopScript
###Hadoop 脚本自动化项目 <br />

####1. AutoDeployHadoop -- 自动部署集群脚本
                     
   * `使用条件`：所有节点局域网互连、已运行SSH服务且允许root远程登陆、拥有相同的root密码
   * `使用方法`：下载jdk-7u45-linux-x64.tar.gz和hadoop-2.7.2.tar.gz，放到AutoDeployHadoop目录，以root用户执行 run.sh
   * `注意事项`：
     * 可以根据需要替换jdk和hadoop安装包，自定义版本，请保持jdk与hadoop安装包“文件名称”为官方名字
     * 安装后的hadoop默认路径为/opt/hadoop-x.x.x，需手动格式化hdfs并启动hdfs和yarn服务
