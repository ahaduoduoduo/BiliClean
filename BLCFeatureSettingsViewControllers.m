#import "BLCFeatureSettingsViewControllers.h"
#import "BLCCDNManager.h"
#import "BLCTabManager.h"

static UIColor *BLCFeatureAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:(102.0 / 255.0) blue:(153.0 / 255.0) alpha:1.0];
}

static UITableViewCell *BLCFeatureCell(UITableViewCellStyle style) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

@interface BLCCDNSettingsViewController ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *liveResults;
@property (nonatomic, copy) NSString *progressText;
@end

@implementation BLCCDNSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"CDN 加速";
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.allowsSelectionDuringEditing = YES;
    self.liveResults = [NSMutableDictionary dictionary];
    self.progressText = @"";
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(configurationChanged:)
                                                 name:BLCCDNConfigurationDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(configurationChanged:)
                                                 name:BLCCDNSpeedTestDidUpdateNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configurationChanged:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 3;
    }
    if (section == 1) {
        return [BLCCDNManager sharedManager].selectedHosts.count;
    }
    return [BLCCDNManager sharedManager].candidates.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"测速";
    if (section == 1) return @"已选 CDN（最多 3 个，可拖动）";
    return @"候选 CDN";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"测速全程匿名。每个 CDN 最多读取 2 MiB，完整测试最多约 38 MiB。";
    }
    if (section == 1) {
        return @"第 1 名用于 base_url，第 2、3 名依次用于 backup_url。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BLCCDNManager *manager = [BLCCDNManager sharedManager];
    UITableViewCell *cell = BLCFeatureCell(UITableViewCellStyleSubtitle);
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"启用 CDN 替换";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = manager.isEnabled;
            toggle.onTintColor = BLCFeatureAccentColor();
            [toggle addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"测速 BV 号";
            cell.detailTextLabel.text = manager.sampleBVID;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = manager.isTesting ? @"停止测速" : @"自动测速并选择前三名";
            cell.textLabel.textColor = manager.isTesting ? [UIColor systemRedColor] : BLCFeatureAccentColor();
            cell.detailTextLabel.text = self.progressText;
        }
        return cell;
    }

    if (indexPath.section == 1) {
        NSArray<NSString *> *selected = manager.selectedHosts;
        NSString *host = selected[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)indexPath.row + 1, [manager displayNameForHost:host]];
        cell.detailTextLabel.text = host;
        cell.showsReorderControl = YES;
        return cell;
    }

    NSDictionary *candidate = manager.candidates[indexPath.row];
    NSString *host = candidate[@"host"];
    cell.textLabel.text = candidate[@"name"];
    NSString *live = self.liveResults[host];
    NSNumber *speed = manager.lastSpeeds[host];
    cell.detailTextLabel.text = live ?: (speed ? [NSString stringWithFormat:@"%.2f MB/s · %@", speed.doubleValue, host] : host);
    cell.accessoryType = [manager.selectedHosts containsObject:host]
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView setEditing:YES animated:NO];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section != 1) {
        return sourceIndexPath;
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray<NSString *> *hosts = [[BLCCDNManager sharedManager].selectedHosts mutableCopy];
    NSString *host = hosts[sourceIndexPath.row];
    [hosts removeObjectAtIndex:sourceIndexPath.row];
    [hosts insertObject:host atIndex:destinationIndexPath.row];
    [[BLCCDNManager sharedManager] setSelectedHosts:hosts];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BLCCDNManager *manager = [BLCCDNManager sharedManager];
    if (indexPath.section == 0 && indexPath.row == 1) {
        [self editSampleBVID];
        return;
    }
    if (indexPath.section == 0 && indexPath.row == 2) {
        if (manager.isTesting) {
            [manager cancelSpeedTest];
        } else {
            [self startSpeedTest];
        }
        return;
    }
    if (indexPath.section != 2) {
        return;
    }
    NSString *host = manager.candidates[indexPath.row][@"host"];
    NSMutableArray<NSString *> *selected = [manager.selectedHosts mutableCopy];
    if ([selected containsObject:host]) {
        [selected removeObject:host];
    } else if (selected.count < 3) {
        [selected addObject:host];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"最多选择 3 个 CDN"
                                                                       message:@"先取消一个已选 CDN，再添加新的候选。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [manager setSelectedHosts:selected];
    [self.tableView reloadData];
}

- (void)enabledChanged:(UISwitch *)sender {
    [[BLCCDNManager sharedManager] setEnabled:sender.isOn];
}

- (void)editSampleBVID {
    BLCCDNManager *manager = [BLCCDNManager sharedManager];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"测速 BV 号"
                                                                   message:@"使用公开视频，不需要登录。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = manager.sampleBVID;
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSError *error = nil;
        if (![manager setSampleBVID:alert.textFields.firstObject.text error:&error]) {
            [weakSelf showMessage:error.localizedDescription];
        }
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startSpeedTest {
    self.liveResults = [NSMutableDictionary dictionary];
    self.progressText = @"正在获取匿名播放地址…";
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [[BLCCDNManager sharedManager] startSpeedTestWithProgress:^(NSUInteger completed,
                                                               NSUInteger total,
                                                               NSString *host,
                                                               NSNumber *speed,
                                                               NSString *errorMessage) {
        weakSelf.progressText = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)completed, (unsigned long)total];
        weakSelf.liveResults[host] = speed
            ? [NSString stringWithFormat:@"%.2f MB/s · %@", speed.doubleValue, host]
            : [NSString stringWithFormat:@"%@ · %@", errorMessage ?: @"失败", host];
        [weakSelf.tableView reloadData];
    } completion:^(NSArray<NSString *> *selectedHosts,
                   NSDictionary<NSString *,NSNumber *> *speeds,
                   NSError *error) {
        weakSelf.progressText = error
            ? error.localizedDescription
            : [NSString stringWithFormat:@"完成，选出 %lu 个 CDN", (unsigned long)selectedHosts.count];
        [weakSelf.tableView reloadData];
        if (error && error.code != NSURLErrorCancelled) {
            [weakSelf showMessage:error.localizedDescription];
        }
    }];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CDN 加速"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface BLCTabSettingsViewController ()
@property (nonatomic, strong) NSArray<NSString *> *groups;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSDictionary *> *> *itemsByGroup;
@end

@implementation BLCTabSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TAB 板块";
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(refresh)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(snapshotChanged:)
                                                 name:BLCTabConfigurationDidChangeNotification
                                               object:nil];
    [self rebuildItems];
    [[BLCTabManager sharedManager] refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refresh {
    [[BLCTabManager sharedManager] refresh];
}

- (void)snapshotChanged:(NSNotification *)notification {
    [self rebuildItems];
    [self.tableView reloadData];
}

- (void)rebuildItems {
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *map = [NSMutableDictionary dictionary];
    for (NSDictionary *item in [[BLCTabManager sharedManager] cachedItems]) {
        NSString *group = item[@"group"];
        if (group.length == 0) {
            continue;
        }
        if (!map[group]) {
            map[group] = [NSMutableArray array];
            [groups addObject:group];
        }
        [map[group] addObject:item];
    }
    self.groups = groups;
    self.itemsByGroup = map;
}

- (NSInteger)tabSectionCount {
    return MAX((NSInteger)self.groups.count, 1);
}

- (NSInteger)keywordSectionIndex {
    return [self tabSectionCount];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self tabSectionCount] + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == [self keywordSectionIndex]) {
        return (NSInteger)[BLCTabManager sharedManager].tabKeywords.count + 1;
    }
    if (self.groups.count == 0) {
        return 1;
    }
    return self.itemsByGroup[self.groups[section]].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == [self keywordSectionIndex]) {
        return @"关键词移除";
    }
    if (self.groups.count == 0) {
        return @"TAB";
    }
    NSDictionary *first = self.itemsByGroup[self.groups[section]].firstObject;
    return first[@"group_name"] ?: self.groups[section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == [self keywordSectionIndex]) {
        return @"按普通文本匹配每个 TAB 项的完整 JSON，忽略大小写。命中名称、tab_id、URI 或嵌套字段时删除整个 TAB。";
    }
    if (section != [self keywordSectionIndex] - 1) {
        return nil;
    }
    NSDate *date = [[BLCTabManager sharedManager] lastUpdatedAt];
    if (!date) {
        return @"尚未获取 TAB 配置。";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [NSString stringWithFormat:@"更新时间：%@。取消勾选或修改关键词会作用于下一次 TAB 接口响应；已加载的导航需要重启 B站。新增 tab_id 默认显示；没有 tab_id 的项目可使用关键词移除。",
            [formatter stringFromDate:date]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = BLCFeatureCell(UITableViewCellStyleSubtitle);
    if (indexPath.section == [self keywordSectionIndex]) {
        NSArray<NSString *> *keywords = [BLCTabManager sharedManager].tabKeywords;
        if (indexPath.row == (NSInteger)keywords.count) {
            cell.textLabel.text = @"添加关键词";
            cell.textLabel.textColor = BLCFeatureAccentColor();
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = keywords[(NSUInteger)indexPath.row];
            cell.detailTextLabel.text = @"向左滑动可删除";
        }
        return cell;
    }
    if (self.groups.count == 0) {
        cell.textLabel.text = @"正在获取 TAB 配置…";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *item = self.itemsByGroup[self.groups[indexPath.section]][indexPath.row];
    NSString *tabID = item[@"tab_id"];
    cell.textLabel.text = item[@"name"];
    cell.detailTextLabel.text = tabID;
    cell.accessoryType = [[BLCTabManager sharedManager] isTabVisible:tabID]
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == [self keywordSectionIndex]) {
        NSArray<NSString *> *keywords = [BLCTabManager sharedManager].tabKeywords;
        if (indexPath.row == (NSInteger)keywords.count) {
            [self addKeyword];
        }
        return;
    }
    if (self.groups.count == 0) {
        return;
    }
    NSDictionary *item = self.itemsByGroup[self.groups[indexPath.section]][indexPath.row];
    NSString *tabID = item[@"tab_id"];
    BLCTabManager *manager = [BLCTabManager sharedManager];
    [manager setTabID:tabID visible:![manager isTabVisible:tabID]];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != [self keywordSectionIndex]) {
        return NO;
    }
    return indexPath.row < (NSInteger)[BLCTabManager sharedManager].tabKeywords.count;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete ||
        indexPath.section != [self keywordSectionIndex]) {
        return;
    }
    NSMutableArray<NSString *> *keywords = [[BLCTabManager sharedManager].tabKeywords mutableCopy];
    if (indexPath.row >= (NSInteger)keywords.count) {
        return;
    }
    [keywords removeObjectAtIndex:(NSUInteger)indexPath.row];
    [[BLCTabManager sharedManager] setTabKeywords:keywords];
}

- (void)addKeyword {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加 TAB 关键词"
                                                                   message:@"单个 TAB 的完整 JSON 含有该文本时，删除整个 TAB。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"名称、tab_id、URI 或其他字段";
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"添加"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        NSMutableArray<NSString *> *keywords = [[BLCTabManager sharedManager].tabKeywords mutableCopy];
        NSString *keyword = [alert.textFields.firstObject.text
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (keyword.length == 0) {
            return;
        }
        [keywords addObject:keyword];
        [[BLCTabManager sharedManager] setTabKeywords:keywords];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
