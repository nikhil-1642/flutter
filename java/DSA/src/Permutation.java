public class Permutation {
    public static void permethod(String str,String per){
        if(str.length()==0){
            System.out.println(per);
            return;
        }
        for(int i=0;i<str.length();i++){
            char curr=str.charAt(i);
            String newstr=str.substring(0,i)+str.substring(i+1);
            permethod(newstr,per+curr);
        }
    }
    public static void main(String[] args) {
        String str="abc";
        permethod(str,"");
    }
}
