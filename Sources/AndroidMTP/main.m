#import <Foundation/Foundation.h>
#include <libmtp.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

static NSString *str(const char *s) { return s ? ([NSString stringWithUTF8String:s] ?: @"") : @""; }
static void destroyFiles(LIBMTP_file_t *f) { while (f) { LIBMTP_file_t *n=f->next; LIBMTP_destroy_file_t(f); f=n; } }
static NSString *deviceError(LIBMTP_mtpdevice_t *d) {
    LIBMTP_error_t *e=LIBMTP_Get_Errorstack(d);
    return e ? str(e->error_text) : @"MTP operation failed. Unlock the phone, choose File transfer, and reconnect USB.";
}
static NSDictionary *run(NSDictionary *q) {
    NSString *op=q[@"operation"];
    if ([op isEqual:@"version"]) return @{@"version":str(LIBMTP_VERSION_STRING)};
    LIBMTP_Init();
    LIBMTP_raw_device_t *raw=NULL; int count=0;
    LIBMTP_error_number_t detected=LIBMTP_Detect_Raw_Devices(&raw,&count);
    if (detected!=LIBMTP_ERROR_NONE && detected!=LIBMTP_ERROR_NO_DEVICE_ATTACHED) { free(raw); return @{@"error":@"USB device discovery failed. Close other Android file-transfer apps and reconnect your phone."}; }
    if ([op isEqual:@"devices"]) {
        NSMutableArray *items=[NSMutableArray new];
        for(int i=0;i<count;i++) [items addObject:@{@"bus":@(raw[i].bus_location),@"device":@(raw[i].devnum),@"name":str(raw[i].device_entry.product)}];
        free(raw); return @{@"devices":items};
    }
    LIBMTP_mtpdevice_t *d=NULL;
    for(int i=0;i<count;i++) if(raw[i].bus_location==[q[@"bus"] unsignedIntValue] && raw[i].devnum==[q[@"device"] unsignedIntValue]) { d=LIBMTP_Open_Raw_Device_Uncached(&raw[i]); break; }
    free(raw);
    if (!d) return @{@"error":@"Phone unavailable. Unlock it, select File transfer / Android Auto on USB, and close MacDroid, OpenMTP or other MTP apps."};
    NSDictionary *result=nil;
    char *serialValue=LIBMTP_Get_Serialnumber(d); NSString *serial=str(serialValue); free(serialValue);
    if (q[@"serial"] && ![q[@"serial"] isEqual:serial]) { LIBMTP_Release_Device(d); return @{@"error":@"The connected phone changed. Refresh and select it again."}; }
    uint32_t storage=[q[@"storage"] unsignedIntValue], parent=[q[@"parent"] unsignedIntValue];
    LIBMTP_Clear_Errorstack(d);
    if ([op isEqual:@"storage"]) {
        if (LIBMTP_Get_Storage(d,LIBMTP_STORAGE_SORTBY_NOTSORTED)!=0) result=@{@"error":deviceError(d)};
        else {
            NSMutableArray *items=[NSMutableArray new];
            for(LIBMTP_devicestorage_t *s=d->storage;s;s=s->next) [items addObject:@{@"id":@(s->id),@"name":str(s->StorageDescription),@"capacity":@(s->MaxCapacity),@"free":@(s->FreeSpaceInBytes)}];
            result=@{@"storages":items,@"serial":serial};
        }
    } else if ([op isEqual:@"list"]) {
        LIBMTP_file_t *files=LIBMTP_Get_Files_And_Folders(d,storage,parent);
        if (LIBMTP_Get_Errorstack(d)) result=@{@"error":deviceError(d)};
        else {
            NSMutableArray *items=[NSMutableArray new];
            for(LIBMTP_file_t *f=files;f;f=f->next) [items addObject:@{@"id":@(f->item_id),@"name":str(f->filename),@"size":@(f->filesize),@"folder":@(f->filetype==LIBMTP_FILETYPE_FOLDER)}];
            result=@{@"files":items};
        }
        destroyFiles(files);
    } else if ([op isEqual:@"download"]) {
        NSString *path=q[@"path"];
        if (!serial.length || !q[@"serial"]) result=@{@"error":@"A stable phone serial is required for transfers. Reconnect and refresh."};
        else {
            int fd=open(path.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
            if(fd<0) result=@{@"error":@"The download destination already exists or cannot be created."};
            else {
                uint32_t item=[q[@"item"] unsignedIntValue];
                LIBMTP_file_t *meta=LIBMTP_Get_Filemetadata(d,item);
                if(!meta || meta->storage_id!=storage || ![str(meta->filename) isEqual:q[@"name"]] || meta->filetype==LIBMTP_FILETYPE_FOLDER) result=@{@"error":@"The file changed. Refresh before downloading."};
                else if(LIBMTP_Get_File_To_File_Descriptor(d,item,fd,NULL,NULL)!=0) result=@{@"error":deviceError(d)};
                else { struct stat st; fstat(fd,&st); result=st.st_size==meta->filesize ? @{@"ok":@YES} : @{@"error":@"Incomplete download. Please retry."}; }
                if(meta) LIBMTP_destroy_file_t(meta);
                close(fd);
                if(!result[@"ok"]) unlink(path.fileSystemRepresentation);
            }
        }
    } else if ([op isEqual:@"upload"]) {
        NSString *path=q[@"path"], *name=path.lastPathComponent;
        if(!serial.length || !q[@"serial"]) result=@{@"error":@"A stable phone serial is required for transfers. Reconnect and refresh."};
        else {
            LIBMTP_file_t *files=LIBMTP_Get_Files_And_Folders(d,storage,parent);
            BOOL duplicate=NO;
            for(LIBMTP_file_t *f=files;f;f=f->next) if([str(f->filename) isEqual:name]) duplicate=YES;
            destroyFiles(files);
            if(LIBMTP_Get_Errorstack(d)) result=@{@"error":deviceError(d)};
            else if(duplicate) result=@{@"error":@"A file with this name already exists on the phone. Rename the local file first."};
            else {
                struct stat st; int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
                if(fd<0 || fstat(fd,&st)!=0 || !S_ISREG(st.st_mode)) result=@{@"error":@"Choose a regular file, not a folder or symbolic link."};
                else {
                    LIBMTP_file_t *f=LIBMTP_new_file_t(); f->filename=strdup(name.UTF8String); f->filesize=st.st_size;
                    f->parent_id=parent==0xffffffff ? 0 : parent; f->storage_id=storage; f->filetype=LIBMTP_FILETYPE_UNKNOWN;
                    int status=LIBMTP_Send_File_From_File_Descriptor(d,fd,f,NULL,NULL);
                    result=status==0 ? @{@"ok":@YES} : @{@"error":deviceError(d)};
                    LIBMTP_destroy_file_t(f);
                }
                if(fd>=0) close(fd);
            }
        }
    } else result=@{@"error":@"Unsupported MTP operation."};
    LIBMTP_Release_Device(d); return result ?: @{@"error":@"No MTP response."};
}
int main(void) { @autoreleasepool {
    // libmtp writes diagnostics to stdout. Keep the JSON channel clean.
    int output=dup(STDOUT_FILENO); dup2(STDERR_FILENO,STDOUT_FILENO);
    NSData *input=[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
    id q=[NSJSONSerialization JSONObjectWithData:input options:0 error:nil];
    NSDictionary *result=[q isKindOfClass:NSDictionary.class] ? run(q) : @{@"error":@"Invalid request."};
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    write(output,json.bytes,json.length); close(output);
    return result[@"error"] ? 1 : 0;
} }
