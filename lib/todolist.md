feature:
~~已经有记录的block，点击之后有个地方显示这个block是什么event。不然多个同色event看不出来具体是啥~~
~~data的io~~
~~每行block的时间戳，只有小时，没有日期~~
统计页面
编辑event的页面
~~以增量形式写入了，要是又修改了怎么办？还是要使用json来存放和读取，写入可以先在buffer里面写增量的，有空了再解析。这样删改还是在json里完成~~
~~在userprofileLoader里创建一个method，调用后异步地去检查buffer file是不是还有东西，有的话就解析了填充到正式文件里。程序初始化的时候调用一次，之后有操作的话再调用~~
选择加载某一天前后几天的DayRecord
~~加载的view，能不能不从头显示，而是从中间开始显示？（前七天后七天，得往下翻七页才能翻到当天~~
~~固定窗口大小~~，让窗口置顶
appBar的文字，跟俩按钮离得太近了，往左边去一点
给EditPage里面的每一个EventInfoEditView之间加一点点空隙，然后加上可以上下拖动修改顺序的功能
新增的eventInfo也得更新到mainView的buttonListView里
刷新不起作用啊
同步数据到服务端（包含冲突处理）
服务端的多端数据合并（包含冲突处理）


bug:
~~跨day的selectBlock，如果是反向的先选未来再选过去，就会出现异常选中的情况~~
~~启动的逻辑有点问题，数据加载逻辑有问题（其实逻辑是合适的，但是问题出在了loader的初始化在后，先给renderDate赋值了当前日期了，导致需要热加载后才能显示loader加载的日期）~~
~~如果bufferFile里面有个很多天前的修改信息，但是现在程序没加载那一天的DayRecord，bufferFile里面的修改信息就没有能修改的对象了~~
~~cancel多选的block似乎还是没法修改第一个(wipe似乎可以正常取消)~~
~~已经有的record没法放进hive，不报错，但是hive里面没东西（是因为selecttedBlock没被更新到DayRecord的events里面，写是走这个events写，没更新就没有新东西写入到hive）~~
~~cancelSelection()还是有点问题，要么是抹掉了第一个，要么是无法取消选中~~
~~切换了tab之后，main tab会自动跳转到最前一天加载的（应该是保持原位置不变动）~~
~~怎么现在选中已有颜色的block，不会改变颜色了？？？~~